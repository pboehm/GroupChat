#!/usr/bin/perl -w

#       functions.pl
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
#		Utility-Datei für häufig gebrauchte Funktionen
#
package functions;

use strict;

sub unpack_pkg {
	###
	# Extrahiert die Teile einer Nachricht
	my $pkg = shift;
	chomp($pkg);

	if ($pkg =~ /^(\w+)#(\d*)#(\d*)#(.*)$/) {
		my %hash;
		$hash{TYPE} = $1;
		$hash{TO} = $2;
		$hash{FROM} = $3;
		$hash{PAYLOAD} = $4;
		return \%hash;
	}
	else {
		return undef;
	}
}


1;
