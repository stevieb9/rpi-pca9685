#!perl
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'RPi::PCA9685' ) || print "Bail out!\n";
}

diag( "Testing RPi::PCA9685 $RPi::PCA9685::VERSION, Perl $], $^X" );
