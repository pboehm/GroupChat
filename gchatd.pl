#!/usr/bin/perl -w

#       gchatd.pl
#
#       Copyright 2010 Philipp Böhm <philipp-boehm@live.de>
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with this program; if not, write to the Free Software
#       Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#       MA 02110-1301, USA.
#
#		GroupChat-Daemon
#
#		Chat-Server der die Nachrichten von Clients annimmt und verteilt,
#		sowie die Clients steuert
#
#		TODO: Wenn ein Client die Verbindung beendet, soll er in der
#		Datenbank deaktiviert werden
#
chdir( dirname($0) );

use strict;
use IO::Socket;
use Socket;
use DBI;
use File::Basename;
use Getopt::Long;
use functions;

$SIG{CHLD} = 'IGNORE';

################################################################################
#################### Kommandozeilenparameter parsen ############################
################################################################################
my %PARAMS = ();
GetOptions(
    \%PARAMS,
    "help" => \&help,
    "verbose",
);

################################################################################
#################### Client-Pipes erstellen ####################################
################################################################################
print "Starte GroupChat-Chatserver ...\n";

print "Erzeuge Pipes für die Kommunikation mit den geforkten Childs\n";
my @CLIENT_PIPES;
for my $i ( 0 .. 30 ) {
    my %hash;
    my ( $PIPE_R, $PIPE_W );
    pipe( $PIPE_R, $PIPE_W ) or die "Konnte Pipe $i nicht erstellen";
    $PIPE_W->autoflush(1);
    $hash{"WRITER"} = \$PIPE_W;
    $hash{"READER"} = \$PIPE_R;

    push( @CLIENT_PIPES, \%hash );
}

printf "Pipes: %s\n", scalar(@CLIENT_PIPES);

################################################################################
###################### Verbindung zur Nutzerdatenbank aufbauen #################
################################################################################
print "Baue Verbindung zur Nutzerdatenbank auf\n";
my $dbargs = { AutoCommit => 1, PrintError => 1 };
my $dbh = DBI->connect( "dbi:SQLite:dbname=gchatd_user.db", "", "", $dbargs );

# Nutzerstatus setzen
print "Setze den Nutzerstatus auf inaktiv\n";
$dbh->do('UPDATE user SET is_active = 0;');

# Anzahl Nutzer auslesen
my $stmt = $dbh->prepare('SELECT COUNT(*) FROM user;');
$stmt->execute();
printf "existierende Nutzer: %s\n", ( $stmt->fetchrow_array )[0];

################################################################################
############################## DISPATCHER ######################################
################################################################################

###
# Sammel-Pipe zum Zuführen der Nachrichten an den Dispatcher
print "Erstelle Sammel-Pipe\n";
pipe( CONCENTRATOR_R, CONCENTRATOR_W ) or die "pipe: $!";
CONCENTRATOR_W->autoflush(1);

###
# Dispatcher abspalten
print "Forke den Dispatcher ...\n";
my $dispatcher = fork();
if ( !$dispatcher ) {
    die "Failed to fork the Dispatcher $!" unless defined $dispatcher;

    my $sock_nr = $dbh->prepare('SELECT sock_nr FROM user WHERE uid = ?;');

    while ( my $pkg = <CONCENTRATOR_R> ) {

        my $pkg_ref = unpack_pkg($pkg);
        next unless $pkg_ref;

        # Socket-Nr ermitteln
        $sock_nr->execute( $pkg_ref->{TO} );
        my $nr = ( $sock_nr->fetchrow_array )[0];
        next unless $nr;

        my $pipe = ${ $CLIENT_PIPES[$nr]->{"WRITER"} };
        print $pipe $pkg;

    }

    close(CONCENTRATOR_R);
    exit(0);
}

################################################################################
#################### Socket erstellen und binden ###############################
################################################################################
print "Erstelle Socket und binde an Port\n";
my $SERVER = IO::Socket::INET->new(
    LocalPort => 12345,
    Type      => SOCK_STREAM,
    Reuse     => 1,
    Listen    => 10
) or die "Konnte Server nicht an Port binden $@\n";

################################################################################
################## Client-Verarbeitung #########################################
################################################################################

# SQL-Handles
my $login_user =
  $dbh->prepare('SELECT COUNT(*) FROM user WHERE uid = ? AND pwd = ?;');
my $check_sock_nr_exists =
  $dbh->prepare('SELECT COUNT(*) FROM user WHERE sock_nr = ?;');
my $set_sock_nr = $dbh->prepare(
    'UPDATE user SET sock_nr = ?, is_active = 1
	 WHERE uid = ?;'
);
my $create_user = $dbh->prepare(
    'INSERT INTO user (username, uid, pwd)
	 VALUES (?, (SELECT MAX(uid)+1 FROM user), ?);'
);
my $select_uid = $dbh->prepare('SELECT uid FROM user WHERE username = ?;');


##################################
# Client-Verbindungen initiieren #
##################################
print "Warte auf eingehende Client-Verbindungen\n";
while ( my $CLIENT = $SERVER->accept() ) {

    ###
    # Gegenstelle des Sockets bestimmen
    my $sock_end = getpeername($CLIENT);
    my ( $port, $iaddr ) = unpack_sockaddr_in($sock_end);
    printf "\nEingehender Request von %s:%s\n", inet_ntoa($iaddr), $port;

    # Paket beziehen
    my $login_pkg = <$CLIENT>;
    my $pkg_ref   = unpack_pkg($login_pkg);
    next unless $pkg_ref;

    if ( $pkg_ref->{TYPE} =~ /^REGISTER$/ ) {
        ##############################
        # Nutzer anlegen #############
        ##############################
        print "Versuch des Anlegens eines Nutzers\n";
        if ( $pkg_ref->{PAYLOAD} =~ /username:(.*)\|hash:(.*)$/ ) {
            $create_user->execute( $1, $2 );
            printf "Nutzer %s erfolgreich angelegt\n", $1 if $create_user->rows;

            $select_uid->execute($1);
            my $uid = ( ( $select_uid->fetchrow_array )[0] );

            print $CLIENT build_pkg( TYPE => "REGISTER", PAYLOAD => $uid );
            printf "Nutzer %s hat die UID %s\n", $1, $uid;
            next;
        }
        else {
            print $CLIENT build_pkg( PAYLOAD => "Malformed Register Request" );
            print "Fehlerhafter Registrierungsversuch\n";
            next;
        }

    }

    ##############################
    # Nutzer authentifizieren ####
    ##############################
    next unless $pkg_ref->{TYPE} =~ /^LOGIN$/;

    my $uid  = $pkg_ref->{FROM};
    my $hash = $pkg_ref->{PAYLOAD};
    print "UID: $uid\n";
    print "HASH: $hash\n";

    # authentifizieren
    $login_user->execute( $uid, $hash );
    unless ( ( $login_user->fetchrow_array )[0] ) {
        print $CLIENT build_pkg(
            TYPE    => "ERROR",
            TO      => $uid,
            PAYLOAD => "Login unsuccessful"
        );
        print "Login fehlerhaft\n";
        next;
    }
    else {
        print $CLIENT build_pkg(
            TYPE    => "INFORM",
            TO      => $uid,
            PAYLOAD => "Login successful"
        );
        print "erfolgreich authentifiziert\n";
    }

    # Socket-Nr generieren und entsprechende Pipe zuweisen
    my $sock_nr;
    while (1) {
        $sock_nr = int( rand @CLIENT_PIPES );
        next unless $sock_nr;
        $check_sock_nr_exists->execute($sock_nr);
        next if ( ( $check_sock_nr_exists->fetchrow_array )[0] );
        last;
    }
    $set_sock_nr->execute( $sock_nr, $uid );
    printf "Socketnr: %s\n", $sock_nr;

    my $MESSAGE_RECEIVER = ${ $CLIENT_PIPES[$sock_nr]->{"READER"} };

    ###########################
    # Sender erstellen ########
    ###########################
    print "Forke Sender-Process\n";

    my $sender = fork;
    if ( !$sender ) {
        die "Failed to fork the Sender $!" unless defined $sender;
        close($SERVER);

        while ( defined( my $message = <$MESSAGE_RECEIVER> ) ) {
            my $parts = unpack_pkg($message);

            ###
            # Shutdown-Nachricht
            last if $parts->{"TYPE"} =~ /SENDER_SHUTDOWN/;

            ###
            # Nachricht senden
            printf "%s >> %s %s:%s\n", $parts->{"FROM"}, $parts->{"TO"},
              $parts->{"TYPE"}, $parts->{"PAYLOAD"};
            print $CLIENT $message;
        }
        close($CLIENT);
        printf "Sender von %s geschlossen\n", $uid;

        exit;    # Ende des Sender-Processes
    }

    ###########################
    # Empfänger erstellen #####
    ###########################
    print "Forke Empfänger-Process\n";

    my $receiver = fork;
    if ( !$receiver ) {
        die "Failed to fork the Receiver $!" unless defined $receiver;
        close($SERVER);

        while (<$CLIENT>) {
            print CONCENTRATOR_W $_;
        }
        close($CLIENT);

        ###
        # Sender-Prozess zum Beenden auffordern
        printf "Empfänger von %s geschlossen\n", $uid;
        print CONCENTRATOR_W build_pkg(
            TYPE    => "SENDER_SHUTDOWN",
            TO      => $uid,
            PAYLOAD => "Socket-Shutdown"
        );

        exit;    # Ende des Receiver-Processes
    }

}
continue {
    close($CLIENT);
}

################################################################################
########################## Funktionsdefinitionen ###############################
################################################################################

sub help {
    print << "EOF";

Copyright 2011 Philipp Böhm

GroupChat-Daemon ist ein Chat-Server, der Clients authentifiziert
und die erhaltenen Nachrichten zustellt.
    
Usage: $0 [Optionen]

   --help               : Diesen Hilfetext ausgeben
   --verbose            : erweiterte Ausgaben
                          
EOF
    exit();
}
