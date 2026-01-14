# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # Variables from core/config, used in other files
# ============================================================================
# Helpers: macOS sleep detection, sparkline, formatting
# ============================================================================

# Cache sleep timestamps to avoid running pmset on every statusline update
# Cache refreshes every 5 minutes
SLEEP_CACHE="${CACHE_DIR}/claude-sleep-times"
SLEEP_CACHE_TTL=300 # 5 minutes

if [ -f "$SLEEP_CACHE" ] && [ $(($(date +%s) - $(stat -f %m "$SLEEP_CACHE" 2>/dev/null || echo 0))) -lt $SLEEP_CACHE_TTL ]; then
    SLEEP_TIMES=$(cat "$SLEEP_CACHE")
else
    # Uses perl for date parsing since macOS awk lacks mktime
    SLEEP_TIMES=$(pmset -g log 2>/dev/null | perl -ne '
        use Time::Local;
        BEGIN { print "["; $n = 0; }
        if (/^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2}).*Sleep\s+Entering Sleep/) {
            my $ts = timelocal($6, $5, $4, $3, $2-1, $1);
            print "," if $n++;
            print $ts;
        }
        END { print "]"; }
    ' 2>/dev/null)
    [ -z "$SLEEP_TIMES" ] && SLEEP_TIMES="[]"
    echo "$SLEEP_TIMES" >"$SLEEP_CACHE" 2>/dev/null
fi

# Sparkline rendering function (uses perl for reliable UTF-8)
render_sparkline() {
    local values="$1" # comma-separated values
    local style="${2:-$SPARKLINE_STYLE}"

    [ -z "$values" ] && return

    echo "$values" | perl -e '
        use utf8;
        binmode STDOUT, ":utf8";
        my $style = $ARGV[0];
        my @blocks = ("▁", "▂", "▃", "▄", "▅", "▆", "▇", "█");
        my @braille = ("⣀", "⣤", "⣶", "⣿");
        my @arrows = ("↓", "↘", "→", "↗", "↑");

        my $line = <STDIN>;
        chomp $line;
        my @vals = split /,/, $line;
        exit unless @vals;

        my ($min, $max) = ($vals[0], $vals[0]);
        for (@vals) { $min = $_ if $_ < $min; $max = $_ if $_ > $max; }
        my $range = $max - $min || 1;

        if ($style eq "braille") {
            for my $v (@vals) {
                my $idx = int(($v - $min) / $range * 3.99);
                print $braille[$idx];
            }
        } elsif ($style eq "blocks") {
            for my $v (@vals) {
                my $idx = int(($v - $min) / $range * 7.99);
                print $blocks[$idx];
            }
        } elsif ($style eq "arrows") {
            for my $i (1..$#vals) {
                my $d = $vals[$i] - $vals[$i-1];
                my $idx = $d < -0.15 ? 0 : $d < -0.05 ? 1 : $d > 0.15 ? 4 : $d > 0.05 ? 3 : 2;
                print $arrows[$idx];
            }
        }
    ' "$style"
}

# Repeat a character n times (avoids spawning seq subprocess)
repeat_char() {
    local char="$1" count="$2"
    [ "$count" -le 0 ] && return
    printf "%${count}s" | tr ' ' "$char"
}

# Format token counts (K notation, no decimals)
fmt_k() {
    if [ "$1" -ge 1000 ]; then
        printf "%dK" "$((($1 + 500) / 1000))"
    else
        echo "$1"
    fi
}

# Format seconds to human readable (with decimals)
format_secs() {
    local secs=$1
    # Handle decimal input
    local int_secs=${secs%.*}
    [ -z "$int_secs" ] && int_secs=0
    if [ "$int_secs" -ge 60 ]; then
        printf "%dm%.0fs" $((int_secs / 60)) "$(echo "$secs - ($int_secs / 60) * 60" | bc)"
    else
        printf "%.1fs" "$secs"
    fi
}
