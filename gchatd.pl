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
$SIG{CHLD} = 'IGNORE';


###
# Pipes für potentielle Nutzer vorhalten
my @CLIENT_PIPES;
for my $i (1..30) {
	my %hash;
	pipe(PIPE_R, PIPE_W) or die "Konnte Pipe $i nicht erstellen";
	$hash{"WRITER"} = *PIPE_W;
	$hash{"READER"} = *PIPE_R;
	$hash{"USED"} = 0;

	push(@CLIENT_PIPES, \%hash);
}

print scalar(@CLIENT_PIPES) . "\n";


###
# Nachrichten von Clients sammeln und zum Senden vorbereiten
pipe(CONCENTRATOR_R, CONCENTRATOR_W) or die "pipe: $!";


my $DISPATCHER_PID = fork();
if (! $DISPATCHER_PID) {
	###
	# Prozess der die Nachrichten von den Clients auf die anderen Clients verteilt
	
	while(<CONCENTRATOR_R>) {
		print "\nFROMSOCK: " . $_;
		for my $hash (@CLIENT_PIPES) {
			my $pipe = $hash->{"WRITER"};
			print ".";
			print $pipe $_;
		}
	}
	
	close(CONCENTRATOR_R);
	exit(0);
}


my $SERVER = IO::Socket::INET->new( LocalPort => 12345,
									Type => SOCK_STREAM,
									Reuse => 1,
									Listen => 10 ) 
	or die "Konnte Server nicht an Port binden $@\n";


while (my $CLIENT = $SERVER->accept()) {

	####
	# Nutzer-ID erstellen
	my $UID;

	while (1) { 
		$UID = int(rand @CLIENT_PIPES);
		next if $CLIENT_PIPES[$UID]->{"USED"} == 1;
		last;
	}
	
	print $UID . "\n";

	$CLIENT_PIPES[$UID]->{"USED"} = 1;
	my $MESSAGE_RECEIVER = $CLIENT_PIPES[$UID]->{"READER"};
	
	###
	# Sender erstellen
	print "Forke Sender-Process\n";

	my $sender = fork;
	if (! $sender) {
		die "Failed to fork the Sender $!" unless defined $sender;
		close($SERVER);
	
		while (<$MESSAGE_RECEIVER>) {
			print "SENDTO: $_";
			#print $CLIENT $_;
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


} continue {
	close($CLIENT);
}
