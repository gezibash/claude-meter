# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034,SC2086  # Variables from core/input, used in output, numeric comparisons
# ============================================================================
# Domain: Resources (progress bar, tokens, cost)
# Provides: domain_resources, text_color
# Requires: total_used, ctx_size, true_pct, has_usage_data, msg_fmt,
#           buffer_fmt, total_fmt, eff_fmt, cost (from core/input)
# ============================================================================

# If no API data, hide resources display entirely
if [ "${has_usage_data:-0}" -eq 0 ]; then
    domain_resources="\033[2m(context data unavailable)\033[0m"
    text_color="\033[37m"
else

    # Progress bar color based on TRUE usage
    if [ $true_pct -lt $CTX_WARN_THRESHOLD ]; then
        fill_color="48;5;34"
        text_color="\033[32m"
    elif [ $true_pct -lt $CTX_HIGH_THRESHOLD ]; then
        fill_color="48;5;220"
        text_color="\033[33m"
    elif [ $true_pct -lt $CTX_CRIT_THRESHOLD ]; then
        fill_color="48;5;208"
        text_color="\033[38;5;208m"
    else
        fill_color="48;5;196"
        text_color="\033[31m"
    fi

    # Progress bar: [used|free|buffer]
    # Calculate widths for each segment
    msg_width=$((total_used * BAR_WIDTH / effective_max))
    pos_buffer_start=$(((effective_max - CTX_BUFFER) * BAR_WIDTH / effective_max))
    buffer_width=$((BAR_WIDTH - pos_buffer_start))
    remaining=$((pos_buffer_start - msg_width))

    # Ensure minimum msg_width of 1 for the position dot when there's any usage
    [ $msg_width -le 0 ] && [ $total_used -gt 0 ] && msg_width=1 && remaining=$((remaining - 1))

    # Safety bounds
    [ $msg_width -lt 0 ] && msg_width=0
    [ $remaining -lt 0 ] && remaining=0

    fg_color="${fill_color/48;5;/38;5;}"

    if [ "$BAR_STYLE" = "blocks" ]; then
        # Block style using Unicode shaded blocks
        bar="│"
        [ $msg_width -gt 0 ] && bar+="\033[${fg_color}m$(repeat_char '█' $msg_width)\033[0m"
        [ $remaining -gt 0 ] && bar+="\033[38;5;240m$(repeat_char '·' $remaining)\033[0m"
        [ $buffer_width -gt 0 ] && bar+="\033[38;5;238m$(repeat_char '~' $buffer_width)\033[0m"
        bar+="│"
    else
        # ASCII style: messages as solid bar with position marker
        bar="┃"
        if [ $msg_width -gt 0 ]; then
            [ $msg_width -gt 1 ] && bar+="\033[${fg_color}m$(repeat_char '━' $((msg_width - 1)))\033[0m"
            bar+="\033[${fg_color}m●\033[0m"
        fi
        [ $remaining -gt 0 ] && bar+="\033[38;5;240m$(repeat_char '─' $remaining)\033[0m"
        [ $remaining -gt 0 ] && [ $buffer_width -gt 0 ] && bar+="\033[38;5;240m│\033[0m"
        [ $buffer_width -gt 0 ] && bar+="\033[38;5;238m$(repeat_char '~' $buffer_width)\033[0m"
        bar+="┃"
    fi

    # Cost formatting
    cost_str=$(printf "\$%.2f" "$cost")

    # Build breakdown - buffer is reserved space shown separately
    breakdown="${text_color}${total_fmt} used\033[0m \033[2m(${buffer_fmt} reserved)\033[0m"

    # Assemble domain output
    domain_resources=$(printf "${bar} ${breakdown} │ ${msg_fmt} / ${eff_fmt} │ \033[1m%d%%\033[0m │ %s" "$true_pct" "$cost_str")

fi # end has_usage_data check
