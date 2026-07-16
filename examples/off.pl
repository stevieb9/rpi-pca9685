#!/usr/bin/env perl

# Park the PCA9685: turn every channel hard off, then stop the oscillator.
#
# A standalone kill switch for when a previous run left the chip driving its
# outputs - for example an SSH session that died mid-fade, leaving the LEDs
# lit. The chip generates its PWM in hardware and holds its last state
# independently of any host process, so simply attaching and calling off() is
# all it takes to stop everything.
#
# Attaching does not disturb the outputs on the way in: new() only wakes the
# chip and enables register auto-increment, it never touches the LED registers,
# so this won't glitch the channels before it turns them off.
#
# Usage: perl off.pl [addr]
#
#     addr    Optional I2C address, decimal or 0x-prefixed hex (default 0x40)

use warnings;
use strict;

use RPi::PWM::PCA9685;

my $addr = shift;

my %args;

if (defined $addr){
    $args{addr} = $addr =~ /^0x/i ? hex($addr) : $addr;
}

my $pca = RPi::PWM::PCA9685->new(%args);

$pca->off;

printf "PCA9685 at 0x%02X parked: all channels off, oscillator stopped\n", $pca->addr;
