# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # Variables from core/input, used in output
# ============================================================================
# Domain: Rhythm (stride ratio, pace, mode)
# Provides: domain_rhythm, stride_str, step_str, mode_str
# Requires: T_* variables (from core/32-transcript-parse.sh)
# ============================================================================

step_str=""
stride_str=""
mode_str=""

# Pace - use pre-computed values from Python parser
if [ -n "$T_PACE_AVG" ] && [ "$T_PACE_AVG" != "0" ] && [ "$T_PACE_AVG" != "0.0" ]; then
    pace_spark=""
    [ -n "$T_PACE_VALS" ] && pace_spark=$(render_sparkline "$T_PACE_VALS")
    step_str=$'\033[1mpace:\033[0m '"$(format_secs "$T_PACE_AVG")"
    [ -n "$pace_spark" ] && step_str+=" $pace_spark"
fi

# Stride - use pre-computed user/claude counts
user_total=${T_USER_TOTAL:-0}
claude_total=${T_CLAUDE_TOTAL:-0}
user_recent=${T_USER_RECENT:-0}
claude_recent=${T_CLAUDE_RECENT:-0}

if [ "$user_total" -gt 0 ] && [ "$claude_total" -gt 0 ]; then
    stride=$(echo "1:1 1:2 1:3 1:4 1:5 1:6 1:7 1:8 2:3 3:4 4:5 5:6 5:8 3:8 2:5 3:5 1:10 1:12 1:15 1:20" | tr ' ' '\n' | awk -v u="$user_total" -v c="$claude_total" '
        BEGIN { actual = u / c; best_diff = 999 }
        { split($0, m, ":"); ratio = m[1] / m[2]
          diff = (actual - ratio) > 0 ? (actual - ratio) : (ratio - actual)
          if (diff < best_diff) { best_diff = diff; best = $0 } }
        END { print best }
    ')

    accel="·"
    if [ "$user_recent" -gt 0 ] && [ "$claude_recent" -gt "$STRIDE_MIN_RESPONSES" ]; then
        delta=$(awk -v ut="$user_total" -v ct="$claude_total" -v ur="$user_recent" -v cr="$claude_recent" '
            BEGIN {
                overall = ut / ct
                recent = ur / cr
                printf "%.3f", recent - overall
            }
        ')
        accel=$(awk -v d="$delta" -v hi="$STRIDE_ACCEL_HIGH" -v lo="$STRIDE_ACCEL_LOW" 'BEGIN {
            if (d > hi) print "«"
            else if (d > lo) print "‹"
            else if (d < -hi) print "»"
            else if (d < -lo) print "›"
            else print "·"
        }')
    fi

    stride_str="\033[1mstride:\033[0m ${stride} ${accel}"
else
    stride_str="\033[1mstride:\033[0m —"
fi

# Mode - directly from parser
if [ -n "$T_MODE" ]; then
    case "$T_MODE" in
    idle)
        mode_str="\033[2mmode: idle\033[0m"
        ;;
    stuck)
        mode_str="\033[1mmode:\033[0m \033[31mstuck\033[0m"
        ;;
    *)
        mode_str="\033[1mmode:\033[0m $T_MODE"
        ;;
    esac
fi

# Assemble domain output
domain_rhythm=""
[ -n "$stride_str" ] && domain_rhythm+="$stride_str"
[ -n "$step_str" ] && [ -n "$domain_rhythm" ] && domain_rhythm+=" │ "
[ -n "$step_str" ] && domain_rhythm+="$step_str"
[ -n "$mode_str" ] && [ -n "$domain_rhythm" ] && domain_rhythm+=" │ "
[ -n "$mode_str" ] && domain_rhythm+="$mode_str"
