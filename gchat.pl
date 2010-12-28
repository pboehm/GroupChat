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
#		GroupChat-Client
#

use strict;
use IO::Socket;

#my @SOCKS;

#for (my $i = 0; $i < 1; $i++) {
	my $socket = IO::Socket::INET->new( PeerAddr => "127.0.0.1",
									PeerPort => 12345,
									Proto => "tcp",
									Type => SOCK_STREAM ) 
	or die "Konnte keine Verbindung zu Server aufbauen $@\n";
	$socket->autoflush(1);

	#die "Konnte nicht forken" unless defined(my $kidpid = fork());
	#if ($kidpid) {
		#while(defined(my $line = <$socket>)) {
			#print "REPLY: $_";
		#}
	#}
	#else {
		#while(defined(my $line = <STDIN>)) {
			#print $socket $line;
		#}
	#}

	for my $i (1..5) {
		print $socket "was anderes schnellere besonders schnelle Nachricht von Client\n";
		#my $back = <$socket>;
		#print $back;
	}

	#sleep(5);
	#while(<$socket>) {
		#print;
	#}

	#push(@SOCKS, \$socket);
	#sleep(5);
#}


#while (1) {
	#my $nmbr = rand @SOCKS;
	#my $sock = ${$SOCKS[$nmbr]}; 
	#print $sock "Nachricht von Client $nmbr\n";
	#sleep(2);
#}

#for my $socket (@SOCKS) {
	#close($socket);
#}
