# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034,SC2086  # Variables from core/input, used in output, numeric comparisons
# ============================================================================
# Domain: Rate Limits (5-hour and 7-day usage with reset times)
# Provides: domain_ratelimits
# Requires: rate_5h_pct, rate_5h_reset, rate_7d_pct, rate_7d_reset (from core/input)
# ============================================================================

# Rate limit color — differential: how far ahead of pace?
# Args: pct target (both integers)
# delta ≤ 10: green, 11-20: yellow, 21-30: orange, >30: red
_rl_color() {
    local pct=$1 target=${2:-0}
    local delta=$((pct - target))
    if [ "$delta" -le 10 ]; then
        printf "\033[32m"
    elif [ "$delta" -le 20 ]; then
        printf "\033[33m"
    elif [ "$delta" -le 30 ]; then
        printf "\033[38;5;208m"
    else
        printf "\033[31m"
    fi
}

# Format reset timestamp as friendly date ("resets Fri 5pm", "resets 2:30pm", "resets now")
_rl_fmt_reset() {
    local reset_at=$1 now
    now=$(date +%s)
    local diff=$((reset_at - now))
    [ "$diff" -le 0 ] && printf "now" && return

    # Today: show relative ("in 2h", "in 45m")
    # Future: show absolute ("tmrw 5pm", "Fri 3pm")
    local today_start tomorrow_start day_after
    today_start=$(date -v0H -v0M -v0S +%s)
    tomorrow_start=$((today_start + 86400))
    day_after=$((today_start + 172800))

    if [ "$reset_at" -lt "$tomorrow_start" ]; then
        # Today — relative time
        if [ "$diff" -ge 3600 ]; then
            local h=$((diff / 3600)) m=$(((diff % 3600) / 60))
            if [ "$m" -gt 0 ]; then
                printf "in %dh%dm" "$h" "$m"
            else
                printf "in %dh" "$h"
            fi
        elif [ "$diff" -ge 60 ]; then
            printf "in %dm" $((diff / 60))
        else
            printf "in %ds" "$diff"
        fi
    else
        # Future — absolute day + time
        local hour minute ampm hour_str
        hour=$(date -r "$reset_at" +%H)
        minute=$(date -r "$reset_at" +%M)
        ampm="am"
        hour=$((10#$hour))
        [ "$hour" -ge 12 ] && ampm="pm"
        [ "$hour" -gt 12 ] && hour=$((hour - 12))
        [ "$hour" -eq 0 ] && hour=12
        if [ "$minute" = "00" ]; then
            hour_str="${hour}${ampm}"
        else
            hour_str="${hour}:${minute}${ampm}"
        fi

        if [ "$reset_at" -lt "$day_after" ]; then
            printf "tmrw %s" "$hour_str"
        else
            printf "%s %s" "$(date -r "$reset_at" +%a)" "$hour_str"
        fi
    fi
}

# Compute pace delta: actual% vs linear target to reach 100% by reset
# Returns "▼N%" (under pace, green) or "▲N%" (over pace, red) or "" if no reset
_rl_pace() {
    local pct=$1 reset_at=$2 window_secs=$3
    [ "$reset_at" -le 0 ] 2>/dev/null && return
    local now
    now=$(date +%s)
    local remaining=$((reset_at - now))
    [ "$remaining" -le 0 ] && return
    local elapsed=$((window_secs - remaining))
    [ "$elapsed" -le 0 ] && return
    local target=$((elapsed * 100 / window_secs))
    printf "%d" "$target"
}

# Build rate limits segments
_rl_parts=""

if [ "${rate_5h_pct%.*}" -ge 0 ] 2>/dev/null; then
    _5h_int=${rate_5h_pct%.*}
    _5h_target=$(_rl_pace "$_5h_int" "$rate_5h_reset" 18000)
    _5h_color=$(_rl_color "$_5h_int" "${_5h_target:-0}")
    _5h_reset=""
    [ "$rate_5h_reset" -gt 0 ] && _5h_reset=" \033[2mresets $(_rl_fmt_reset "$rate_5h_reset")\033[0m"
    _5h_target_str=""
    [ -n "$_5h_target" ] && _5h_target_str=" \033[2m(${_5h_target}%%)\033[0m"
    _rl_parts+="${_5h_color}5h: ${_5h_int}%%\033[0m${_5h_reset}${_5h_target_str}"
fi

if [ "${rate_7d_pct%.*}" -ge 0 ] 2>/dev/null; then
    [ -n "$_rl_parts" ] && _rl_parts+=" │ "
    _7d_int=${rate_7d_pct%.*}
    _7d_target=$(_rl_pace "$_7d_int" "$rate_7d_reset" 604800)
    _7d_color=$(_rl_color "$_7d_int" "${_7d_target:-0}")
    _7d_reset=""
    [ "$rate_7d_reset" -gt 0 ] && _7d_reset=" \033[2mresets $(_rl_fmt_reset "$rate_7d_reset")\033[0m"
    _7d_target_str=""
    [ -n "$_7d_target" ] && _7d_target_str=" \033[2m(${_7d_target}%%)\033[0m"
    _rl_parts+="${_7d_color}7d: ${_7d_int}%%\033[0m${_7d_reset}${_7d_target_str}"
fi

# Assemble domain output (only if we have rate limit data)
domain_ratelimits=""
if [ -n "$_rl_parts" ]; then
    # shellcheck disable=SC2059
    domain_ratelimits=$(printf "$_rl_parts")
fi
