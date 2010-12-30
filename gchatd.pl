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

use strict;

use IO::Socket;
use Socket;
use POSIX qw(:sys_wait_h);
use DB_File;
use DBI;
use File::Basename;
require functions;

chdir(dirname($0));
$SIG{CHLD} = 'IGNORE';


print "Starting gchatd ...\n";

################################################################################
#################### Client-Pipes erstellen ####################################
################################################################################
print "Erzeuge Pipes für die Kommunikation mit den geforkten Childs\n";
my @CLIENT_PIPES;
for my $i (0..30) {
	my %hash;
	my ($PIPE_R, $PIPE_W);
	pipe($PIPE_R, $PIPE_W) or die "Konnte Pipe $i nicht erstellen";
	$PIPE_W->autoflush(1);
	$hash{"WRITER"} = \$PIPE_W;
	$hash{"READER"} = \$PIPE_R;
	$hash{"USED"} = 0;

	push(@CLIENT_PIPES, \%hash);
}

printf "Pipes: %s\n", scalar(@CLIENT_PIPES);

################################################################################
###################### Verbindung zur Nutzerdatenbank aufbauen #################
################################################################################
print "Baue Verbindung zur Nutzerdatenbank auf\n";
my $dbargs = {AutoCommit => 1, PrintError => 1};
my $dbh = DBI->connect("dbi:SQLite:dbname=gchatd_user.db", "", "", $dbargs);

# Nutzerstatus setzen
print "Setze den Nutzerstatus auf inaktiv\n";
$dbh->do('UPDATE user SET is_active = 0;');

# Anzahl Nutzer auslesen
my $stmt = $dbh->prepare('SELECT COUNT(*) FROM user;');
$stmt->execute();
printf "existierende Nutzer: %s\n", ($stmt->fetchrow_array)[0];

################################################################################
############################## DISPATCHER ######################################
################################################################################

###
# Sammel-Pipe zum Zuführen der Nachrichten an den Dispatcher
print "Erstelle Sammel-Pipe\n";
pipe(CONCENTRATOR_R, CONCENTRATOR_W) or die "pipe: $!";
CONCENTRATOR_W->autoflush(1);

###
# Dispatcher abspalten
print "Forke den Dispatcher ...\n";
my $dispatcher = fork();
if (! $dispatcher) {
	die "Failed to fork the Dispatcher $!" unless defined $dispatcher;

	my $sock_nr = $dbh->prepare('SELECT sock_nr FROM user WHERE uid = ?;');
	
	while (my $pkg = <CONCENTRATOR_R>) {

		my $pkg_ref = functions::unpack_pkg($pkg);
		next unless $pkg_ref;

		$sock_nr->execute($pkg_ref->{TO});
		my $nr = ($sock_nr->fetchrow_array)[0];
		next unless $nr;
		
		my $pipe = ${$CLIENT_PIPES[$nr]->{"WRITER"}};
		print $pipe $pkg;
		
	}
	
	close(CONCENTRATOR_R);
	exit(0);
}

################################################################################
#################### Socket erstellen und binden ###############################
################################################################################
print "Erstelle Socket und binde an Port\n";
my $SERVER = IO::Socket::INET->new( LocalPort => 12345,
									Type => SOCK_STREAM,
									Reuse => 1,
									Listen => 10 ) 
	or die "Konnte Server nicht an Port binden $@\n";


################################################################################
################## Client-Verarbeitung #########################################
################################################################################

# SQL-Handles
my $login_user = $dbh->prepare('SELECT COUNT(*) FROM user WHERE uid = ? AND pwd = ?;');
my $check_sock_nr_exists = $dbh->prepare('SELECT COUNT(*) FROM user WHERE sock_nr = ?;');
my $set_sock_nr = $dbh->prepare('UPDATE user SET sock_nr = ?, is_active = 1
								 WHERE uid = ?;');

print "Warte auf eingehende Client-Verbindungen\n";
while (my $CLIENT = $SERVER->accept()) {

	my $sock_end = getpeername($CLIENT);
	my ($port, $iaddr) = unpack_sockaddr_in($sock_end);
	printf "\nEingehender Request von %s:%s\n", inet_ntoa($iaddr), $port;

	####
	# Nutzer authentifizieren

	# Paket beziehen
	my $login_pkg = <$CLIENT>;

	my $pkg_ref = functions::unpack_pkg($login_pkg);
	next unless $pkg_ref;
	next unless $pkg_ref->{TYPE} =~ /^LOGIN$/;

	my $uid = $pkg_ref->{FROM};
	my $hash = $pkg_ref->{PAYLOAD};
	print "UID: $uid\n";
	print "HASH: $hash\n";

	# authentifizieren
	$login_user->execute($uid, $hash);
	unless (($login_user->fetchrow_array)[0]) {
		print "Login fehlerhaft\n";
		next;
	}
	print "erfolgreich authentifiziert\n";
	
	# Socket-Nr generieren und entsprechende Pipe zuweisen
	my $sock_nr;
	while (1) {
		$sock_nr = int(rand @CLIENT_PIPES);
		next unless $sock_nr;
		$check_sock_nr_exists->execute($sock_nr);
		next if (($check_sock_nr_exists->fetchrow_array)[0]);
		last;
	}
	$set_sock_nr->execute($sock_nr, $uid);
	printf "Socketnr: %s\n", $sock_nr;


	$CLIENT_PIPES[$sock_nr]->{"USED"} = 1;
	my $MESSAGE_RECEIVER = ${$CLIENT_PIPES[$sock_nr]->{"READER"}};
	
	###
	# Sender erstellen
	print "Forke Sender-Process\n";

	my $sender = fork;
	if (! $sender) {
		die "Failed to fork the Sender $!" unless defined $sender;
		close($SERVER);
	
		while (<$MESSAGE_RECEIVER>) {
			print "SENDTO: $_";
			print $CLIENT $_;
		}
		close($CLIENT);
		
		exit; # Ende des Sender-Processes
	}

	###
	# Empfänger erstellen
	print "Forke Empfänger-Process\n";

	my $receiver = fork;
	if (! $receiver) {
		die "Failed to fork the Receiver $!" unless defined $receiver;
		close($SERVER);

		while (<$CLIENT>) {
		
			print CONCENTRATOR_W $_;
		}
		close($CLIENT);
		
		exit; # Ende des Receiver-Processes
	}


}
continue {
	close($CLIENT);
}
