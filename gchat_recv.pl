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

my $socket = IO::Socket::INET->new( PeerAddr => "127.0.0.1",
								PeerPort => 12345,
								Proto => "tcp",
								Type => SOCK_STREAM ) 
or die "Konnte keine Verbindung zu Server aufbauen $@\n";
$socket->autoflush(1);

my $login_msg = sprintf "LOGIN#0#101#22ed6eeb765ed5a87ce0fea112dc3125\n";
print $socket $login_msg;

while(<$socket>) {
	print;
}
