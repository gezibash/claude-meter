# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # Variables from core/input, used in output
# ============================================================================
# Domain: Session (git branch, model, duration)
# Provides: domain_session, git_str, dur_str
# Requires: cwd, sid, model, T_INACTIVE_SECS (from core/32-transcript-parse.sh)
# ============================================================================

# Git info (branch name dim/white, not colored)
cd "$cwd" 2>/dev/null || cd /
if git rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    # Ahead/behind origin
    upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
    if [ -n "$upstream" ]; then
        ahead=$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)
        behind=$(git rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo 0)
        sync=""
        [ "$ahead" -gt 0 ] && sync+="↑${ahead}"
        [ "$behind" -gt 0 ] && sync+="↓${behind}"
        [ -z "$sync" ] && sync="✓"
    else
        sync="○"
    fi

    # Lines added/removed
    diff_stats=$(git diff --numstat HEAD 2>/dev/null | awk '{a+=$1; d+=$2} END {print a+0, d+0}')
    lines_add=$(echo "$diff_stats" | cut -d' ' -f1)
    lines_del=$(echo "$diff_stats" | cut -d' ' -f2)

    # Time since last commit
    last_commit=$(git log -1 --format=%ct 2>/dev/null)
    if [ -n "$last_commit" ]; then
        now=$(date +%s)
        diff=$((now - last_commit))
        if [ $diff -lt 60 ]; then
            commit_ago="${diff}s"
        elif [ $diff -lt 3600 ]; then
            commit_ago="$((diff / 60))m"
        elif [ $diff -lt 86400 ]; then
            commit_ago="$((diff / 3600))h"
        else
            commit_ago="$((diff / 86400))d"
        fi
    else
        commit_ago="-"
    fi

    # Build git string
    if [ "$lines_add" -eq 0 ] && [ "$lines_del" -eq 0 ]; then
        git_str="\033[2m${branch}\033[0m ${sync} \033[2m${commit_ago}\033[0m"
    else
        git_str="\033[2m${branch}\033[0m \033[32m+${lines_add}\033[0m/\033[31m-${lines_del}\033[0m ${sync} \033[2m${commit_ago}\033[0m"
    fi
else
    git_str="\033[2m-\033[0m"
fi

# Session duration (subtract inactive time from total)
sf="${CACHE_DIR}/claude-session-${sid}"
if [ ! -f "$sf" ]; then
    date +%s >"$sf"
fi
start=$(cat "$sf" 2>/dev/null)
# Handle both epoch (numeric) and ISO format (from Go version)
if ! [[ "$start" =~ ^[0-9]+$ ]]; then
    start=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${start%%+*}" "+%s" 2>/dev/null || date +%s)
fi

# Use pre-computed inactive time from Python parser
inactive_secs=${T_INACTIVE_SECS:-0}

dur=$(($(date +%s) - start - inactive_secs))
[ $dur -lt 0 ] && dur=0
h=$((dur / 3600))
m=$(((dur % 3600) / 60))
s=$((dur % 60))
if [ $h -gt 0 ]; then
    dur_str=$'\033[1msess:\033[0m '$(printf "%dh%02dm" $h $m)
elif [ $m -gt 0 ]; then
    dur_str=$'\033[1msess:\033[0m '$(printf "%dm%02ds" $m $s)
else
    dur_str=$'\033[1msess:\033[0m '$(printf "%ds" $s)
fi

# Assemble domain output
domain_session="${git_str} │ \033[36m${model}\033[0m │ ${dur_str}"
