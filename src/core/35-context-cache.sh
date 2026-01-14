# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # Variables from core/input, used in other files
# ============================================================================
# Context Cache: Parse /context output from transcript, cache per-session
# Provides: CTX_SYSTEM_PROMPT, CTX_SYSTEM_TOOLS, CTX_MCP_TOOLS, CTX_MEMORY, CTX_SKILLS
# Requires: transcript, sid (from core/input)
# ============================================================================

# Session-specific cache file
CTX_CACHE_FILE="${CACHE_DIR}/claude-ctx-${sid}.json"
CTX_CACHE_TTL=3600 # 1 hour - refresh if older

# Check if we need to refresh cache
ctx_cache_valid=0
if [ -f "$CTX_CACHE_FILE" ]; then
    cache_age=$(($(date +%s) - $(stat -f %m "$CTX_CACHE_FILE" 2>/dev/null || echo 0)))
    [ $cache_age -lt $CTX_CACHE_TTL ] && ctx_cache_valid=1
fi

# Parse /context from transcript if cache invalid
if [ "$ctx_cache_valid" -eq 0 ] && [ -f "$transcript" ]; then
    ctx_parsed=$(python3 "${CLAUDE_DIR}/context_parser.py" "$transcript" 2>/dev/null)

    # Write cache if parsing succeeded (non-empty and has values)
    if [ -n "$ctx_parsed" ]; then
        echo "$ctx_parsed" >"$CTX_CACHE_FILE"
        ctx_cache_valid=1
    fi
fi

# Read from cache or use defaults
if [ "$ctx_cache_valid" -eq 1 ] && [ -f "$CTX_CACHE_FILE" ]; then
    eval "$(jq -r '
        @sh "CTX_SYSTEM_PROMPT=\(.system_prompt // 0)
        CTX_SYSTEM_TOOLS=\(.system_tools // 0)
        CTX_MCP_TOOLS=\(.mcp_tools // 0)
        CTX_MEMORY=\(.memory // 0)
        CTX_SKILLS=\(.skills // 0)"
    ' "$CTX_CACHE_FILE" 2>/dev/null)"

    # Override CTX_OVERHEAD and CTX_MCP with actual values
    # CTX_OVERHEAD = system prompt + tools only (mem/skill shown separately)
    if [ "${CTX_SYSTEM_PROMPT:-0}" -gt 0 ]; then
        CTX_OVERHEAD=$((CTX_SYSTEM_PROMPT + CTX_SYSTEM_TOOLS))
    fi
    if [ "${CTX_MCP_TOOLS:-0}" -gt 0 ]; then
        CTX_MCP=$CTX_MCP_TOOLS
    fi

fi
