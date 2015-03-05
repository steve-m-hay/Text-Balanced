#!/usr/bin/perl

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
	if ($ENV{PERL_CORE}) {
		chdir('t') if -d 't';
		@INC = qw(../lib);
	}
}

use Test::More tests => 1;

use_ok( 'Text::Balanced' );
