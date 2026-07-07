#!/usr/bin/env perl

# Breathe an LED up and down on one PCA9685 channel.
#
# Usage: perl fade.pl [channel]

use warnings;
use strict;

use RPi::PWM::PCA9685;

my $channel = defined $ARGV[0] ? $ARGV[0] : 0;

my $running = 1;
$SIG{INT} = sub { $running = 0 };

my $pca = RPi::PWM::PCA9685->new(freq => 1000);

printf("fading channel %d at %.1f Hz, Ctrl-C to quit\n", $channel, $pca->freq);

while ($running){
    for (my $duty = 0; $duty <= 4095 && $running; $duty += 15){
        $pca->duty($channel, $duty);
        select(undef, undef, undef, 0.002);
    }
    for (my $duty = 4095; $duty >= 0 && $running; $duty -= 15){
        $pca->duty($channel, $duty);
        select(undef, undef, undef, 0.002);
    }
}

$pca->all_off;

print "\nall channels off\n";
