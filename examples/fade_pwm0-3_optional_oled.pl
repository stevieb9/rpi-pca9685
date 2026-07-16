#!/usr/bin/env perl

# Breathe four LEDs up and down on channels pwm0, pwm1, pwm2 and pwm3.
#
# Wiring (current sourcing, the totem-pole default):
#
#     chip pin -> LED anode -> LED cathode -> resistor -> GND
#
# The pin sources the current, so the LED is lit while the pin is high
# and duty cycle maps straight to brightness - no invert/sink_mode needed.
#
# Each channel fades toward a random brightness at a random speed. When it
# arrives, a fresh random target and speed are chosen, so the four LEDs
# drift independently and never settle into a repeating pattern.
#
# The live PCA9685 status (frequency, drive mode, and a per-channel duty bar
# labelled by LED colour) is drawn in place on the CLI as the LEDs breathe.
#
# If the sibling repo ~/repos/rpi-oled-ssd1306 is present and its module
# builds, the same status is also mirrored onto a 128x64 SSD1306 OLED. The
# OLED is entirely optional - if it's missing or unusable, the fade runs with
# just the CLI display.
#
# Usage: perl fade3.pl

use warnings;
use strict;

use Time::HiRes qw(time);

use RPi::PWM::PCA9685;

use constant PWM_MAX => 4095;

my @channels = (0, 1, 2, 3);

# The four channels drive a red, yellow, green and blue LED; the OLED labels
# each duty bar with its colour (R/Y/G/B) rather than the channel number.
my @colours = ('R', 'Y', 'G', 'B');

my $running = 1;
$SIG{INT} = sub { $running = 0 };

my $pca    = RPi::PWM::PCA9685->new(freq => 1000);

# A single snapshot of the (unchanging) chip config for the OLED header, so
# the drive mode and oscillator are read from the chip rather than hardcoded
my $status = $pca->status;

# Bring up the OLED if the sibling repo is here; undef means "just fade"
my $oled = oled_init();

printf(
    "fading channels %s at %.1f Hz%s, Ctrl-C to quit\n\n",
    join(', ', @channels),
    $status->{freq},
    $oled ? ', mirroring status to the OLED' : '',
);

# Set once the first CLI frame has been drawn, so later frames know to move
# the cursor back up and redraw the block in place rather than scrolling.
my $cli_drawn = 0;

# Per-channel fade state: where each LED is now, where it's heading, and how
# far it moves per tick. Seed every channel with a random target and speed.
my @duty   = (0) x @channels;
my @target = map { random_target() } @channels;
my @speed  = map { random_speed() }  @channels;

# A full OLED frame takes ~90ms to push over I2C, far too slow to run every
# 2ms fade tick, so the status is refreshed a few times a second at most. The
# CLI display shares the same cadence so both panels update in lockstep.
my $last_refresh = 0;

while ($running){
    for my $i (0 .. $#channels){
        # Step toward this channel's target, clamping so we never overshoot.
        if ($duty[$i] < $target[$i]){
            $duty[$i] += $speed[$i];
            $duty[$i] = $target[$i] if $duty[$i] > $target[$i];
        }
        else {
            $duty[$i] -= $speed[$i];
            $duty[$i] = $target[$i] if $duty[$i] < $target[$i];
        }

        # Arrived: pick a fresh random target and speed for the next fade.
        if ($duty[$i] == $target[$i]){
            $target[$i] = random_target();
            $speed[$i]  = random_speed();
        }

        $pca->duty($channels[$i], $duty[$i]);
    }

    if (time - $last_refresh >= 0.25){
        $cli_drawn = cli_status(\@colours, \@duty, $status, $cli_drawn);
        oled_status($oled, \@colours, \@duty, $status) if $oled;
        $last_refresh = time;
    }

    select(undef, undef, undef, 0.002);
}

$pca->all_off;

if ($oled){
    $oled->clear_buffer;
    $oled->string("PCA9685\nall channels off");
    $oled->display;
}

print "\nall channels off\n";

# A random brightness anywhere across the full duty range.
sub random_target {
    return int(rand(PWM_MAX + 1));
}

# Paint one status frame on the CLI: the same header (PWM frequency, drive
# mode and oscillator) and per-channel colour-labelled duty bars that the OLED
# shows. Redrawn in place - once the first frame is down, the cursor is moved
# back up over the block so each refresh overwrites the last without scrolling.
# Returns a true "already drawn" flag for the caller to feed back in next tick.
sub cli_status {
    my ($labels, $duty, $status, $drawn) = @_;

    my @lines;

    push @lines, sprintf("PCA9685  %.0fHz", $status->{freq});
    push @lines, sprintf("%s  osc %gMHz", $status->{drive}, $status->{osc_hz} / 1_000_000);
    push @lines, "";

    for my $i (0 .. $#$labels){
        my $pct    = int($duty->[$i] / PWM_MAX * 100 + 0.5);
        my $filled = int($pct / 10 + 0.5);
        $filled = 10 if $filled > 10;
        my $bar    = ('#' x $filled) . ('.' x (10 - $filled));

        push @lines, sprintf("%s [%s]%3d%%", $labels->[$i], $bar, $pct);
    }

    # Step the cursor back up over the previous frame before repainting.
    print "\033[", scalar(@lines), "A" if $drawn;

    # "\033[K" clears each line to its end so a shorter bar can't leave stale
    # characters behind from the frame underneath it.
    print "\033[K", $_, "\n" for @lines;

    return 1;
}

# Bring up the OLED from the sibling repo, or return undef if it isn't there
# or won't load. Prefer the built (blib) copy so the compiled XS is found.
sub oled_init {
    my $repo = "$ENV{HOME}/repos/rpi-oled-ssd1306";

    return undef if ! -d $repo;

    my $oled;

    my $ok = eval {
        unshift @INC, "$repo/blib/arch", "$repo/blib/lib";
        require RPi::OLED::SSD1306::128_64;
        $oled = RPi::OLED::SSD1306::128_64->new;
        $oled->text_size(1);
        1;
    };

    if (! $ok){
        warn "OLED repo present but not usable, fading without it: $@";
        return undef;
    }

    return $oled;
}

# Paint one status frame: a header with the PWM frequency, drive mode and
# oscillator, then one duty bar per channel labelled by LED colour. Built in
# the buffer and pushed in a single display() call so the panel updates
# without a blank flash.
sub oled_status {
    my ($oled, $labels, $duty, $status) = @_;

    $oled->clear_buffer;

    $oled->string(sprintf("PCA9685  %.0fHz\n", $status->{freq}));
    $oled->string(sprintf("%s  osc %gMHz\n", $status->{drive}, $status->{osc_hz} / 1_000_000));
    $oled->string("\n");

    for my $i (0 .. $#$labels){
        my $pct    = int($duty->[$i] / PWM_MAX * 100 + 0.5);
        my $filled = int($pct / 10 + 0.5);
        $filled = 10 if $filled > 10;
        my $bar    = ('#' x $filled) . ('.' x (10 - $filled));

        $oled->string(sprintf("%s [%s]%3d%%\n", $labels->[$i], $bar, $pct));
    }

    $oled->display;

    return 1;
}

# A random fade speed, in duty units per tick.
sub random_speed {
    return int(rand(20)) + 5;
}
