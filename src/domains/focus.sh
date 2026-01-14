# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # Variables from core/input, used in output
# ============================================================================
# Domain: Focus (file/dir focus, revision tracking)
# Provides: domain_focus, focus_str, rev_str
# Requires: T_* variables (from core/32-transcript-parse.sh)
# ============================================================================

focus_str=""
rev_str=""

# Use pre-computed focus state from Python parser
prev_type="${T_FOCUS_PREV_TYPE:-}"
prev_label="${T_FOCUS_PREV_LABEL:-}"
curr_type="${T_FOCUS_CURR_TYPE:-}"
curr_label="${T_FOCUS_CURR_LABEL:-}"
top_edit_file="${T_TOP_EDIT_FILE:-}"
top_edit_count="${T_TOP_EDIT_COUNT:-0}"

# Build focus indicator with temporal transition
if [ -n "$curr_type" ] && [ "$curr_type" != "none" ]; then
    if [ -z "$prev_type" ] || [ "$prev_type" == "none" ] ||
        { [ "$prev_type" == "$curr_type" ] && [ "$prev_label" == "$curr_label" ]; }; then
        focus_str="\033[1mfocus:\033[0m \033[2m${curr_type}\033[0m ${curr_label}"
    else
        focus_str="\033[1mfocus:\033[0m \033[2m${prev_type}\033[0m ${prev_label} → \033[2m${curr_type}\033[0m ${curr_label}"
    fi
fi

# Build revision indicator
if [ "$top_edit_count" -ge "$REV_THRESHOLD" ] && [ -n "$top_edit_file" ]; then
    rev_str="\033[1medits:\033[0m ${top_edit_file} (${top_edit_count})"
fi

# Assemble domain output
domain_focus=""
[ -n "$focus_str" ] && domain_focus+="$focus_str"
[ -n "$rev_str" ] && [ -n "$domain_focus" ] && domain_focus+=" │ "
[ -n "$rev_str" ] && domain_focus+="$rev_str"
