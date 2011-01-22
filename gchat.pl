#!/usr/bin/perl -w

#       gchat.pl
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
#       GroupChat-Client
#
chdir( dirname($0) );

use strict;
use IO::Socket;
use Getopt::Long;
use File::Basename;
use functions;
use Digest::MD5 qw(md5_hex);

################################################################################
#################### Kommandozeilenparameter parsen ############################
################################################################################
my %PARAMS = (
    "port" => 12345,
    "host" => "127.0.0.1",
);

GetOptions(
    \%PARAMS,
    "help" => \&help,
    "verbose",
    "port=i",
    "host=s",
    "uid=i",
    "username=s",
    "password=s",
    "register",
);

################################################################################
#################### Socket aufbauen ###########################################
################################################################################
my $socket = IO::Socket::INET->new(
    PeerAddr => $PARAMS{"host"},
    PeerPort => $PARAMS{"port"},
    Proto    => "tcp",
    Type     => SOCK_STREAM
) or die "Konnte keine Verbindung zu Server aufbauen $@\n";
$socket->autoflush(1);

################################################################################
#################### Nutzer registrieren #######################################
################################################################################
if ( $PARAMS{"register"} ) {
    die "Sie müssen --username und --password angeben"
      unless ( $PARAMS{"username"} and $PARAMS{"password"} );

    my $pw_hash = md5_hex( $PARAMS{"password"} );
    my $payload = sprintf "username:%s|hash:%s", $PARAMS{"username"}, $pw_hash;

    print $socket build_pkg( TYPE => "REGISTER", PAYLOAD => $payload );

    while ( defined( my $pkg = <$socket> ) ) {
        my $parts = unpack_pkg($pkg);
        if ( $parts->{TYPE} =~ /INFORM/ ) {
            printf "Der Nutzer wurde mit der UID >>%s<< angelegt\n",
              $parts->{PAYLOAD};
        }
    }
    exit 0;
}

################################################################################
################### Authentifizieren############################################
################################################################################
die "Sie müssen --uid und --password angeben"
  unless ( $PARAMS{"uid"} and $PARAMS{"password"} );

unless ( login( \$socket, $PARAMS{"uid"}, $PARAMS{"password"} ) ) {
    print "Login gescheitert\n";
    exit 1;
}
else {
    print "Login erfolgreich\n";
}

################################################################################
######################## Sender Empfänger forken ###############################
################################################################################
die "Konnte nicht forken" unless defined( my $kidpid = fork() );
if ($kidpid) {
    while ( defined( my $line = <$socket> ) ) {
        my $parts = unpack_pkg($line);

        if ( $parts->{TYPE} =~ /MESSAGE/ ) {
            printf "<<<%s: %s\n", $parts->{"FROM"}, $parts->{"PAYLOAD"};
        }
    }
}
else {
    while ( defined( my $line = <STDIN> ) ) {
        chomp($line);

        if ( $line =~ /sendto\s(\d*)\s(.*)$/ ) {
            print $socket build_pkg(
                TYPE    => "MESSAGE",
                FROM    => $PARAMS{"uid"},
                TO      => $1,
                PAYLOAD => $2
            );
        }
        else {
            print "Malformed Command\n";
        }
    }
}

################################################################################
##################### Funktionsdefinition ######################################
################################################################################

sub login {
    ###
    # Authentifiziert den Nutzer am Server
    my $socket   = ${ shift; };
    my $uid      = shift;
    my $password = shift;

    my $pw_hash = md5_hex($password);

    my $login_msg = build_pkg(
        TYPE    => "LOGIN",
        FROM    => $PARAMS{uid},
        PAYLOAD => $pw_hash
    );
    print $socket $login_msg;

    while ( defined( my $line = <$socket> ) ) {
        my $parts = unpack_pkg($line);
        return 0 if $parts->{PAYLOAD} =~ /unsuccessful/;
        return 1 if $parts->{PAYLOAD} =~ /successful/;
        return undef;
    }
}
