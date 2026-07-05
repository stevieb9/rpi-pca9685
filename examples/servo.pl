#!/usr/bin/env perl

# Sweep a hobby servo back and forth on one PCA9685 channel.
#
# Usage: perl servo.pl [channel] [min_us] [max_us]
#
# Widen min/max toward 500-2500 only in small steps; limits vary servo
# to servo, and buzzing at an end stop means you've gone too far.

use warnings;
use strict;

use RPi::PCA9685;

my $channel = defined $ARGV[0] ? $ARGV[0] : 0;
my $min_us  = defined $ARGV[1] ? $ARGV[1] : 1000;
my $max_us  = defined $ARGV[2] ? $ARGV[2] : 2000;

my $running = 1;
$SIG{INT} = sub { $running = 0 };

my $pca = RPi::PCA9685->new(freq => 50);

printf(
    "sweeping channel %d, %d-%d us, Ctrl-C to quit\n",
    $channel,
    $min_us,
    $max_us,
);

# Start at centre
$pca->servo_us($channel, ($min_us + $max_us) / 2);
sleep 1;

while ($running){
    for (my $us = $min_us; $us <= $max_us && $running; $us += 10){
        $pca->servo_us($channel, $us);
        select(undef, undef, undef, 0.02);
    }
    for (my $us = $max_us; $us >= $min_us && $running; $us -= 10){
        $pca->servo_us($channel, $us);
        select(undef, undef, undef, 0.02);
    }
}

# Stop the pulses; the servo goes limp
$pca->servo_us($channel, 0);

print "\nservo released\n";
