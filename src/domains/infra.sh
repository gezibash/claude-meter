# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034,SC2086  # Variables from core/input, used in output, numeric comparisons
# ============================================================================
# Domain: Infra (skills, MCP servers, commands)
# Provides: domain_infra, skills_str, mcp_str, cmds_str
# Requires: cwd, T_* variables (from core/32-transcript-parse.sh)
# ============================================================================

# Skills - local (repo) only, dimmed if available, bold if loaded
local_skills=()

if [ -d "$cwd/.claude/skills" ]; then
    while IFS= read -r skill_file; do
        skill_name=$(basename "$(dirname "$skill_file")")
        local_skills+=("$skill_name")
    done < <(find "$cwd/.claude/skills" -name "SKILL.md" 2>/dev/null)
fi

# Use pre-computed skills from Python parser
skills_loaded_list=" ${T_SKILLS_LOADED:-} "

# Helper to check if skill is loaded
is_loaded() {
    [[ "$skills_loaded_list" == *" $1 "* ]]
}

# Build skills string - ONLY local skills, max 3, hide if none
skills_str=""
local_skill_count=${#local_skills[@]}

if [ "$local_skill_count" -gt 0 ]; then
    skills_str=$'\033[1mskills:\033[0m '
    shown=0

    for skill in "${local_skills[@]}"; do
        [ $shown -ge $MAX_SKILLS_SHOWN ] && break
        if is_loaded "$skill"; then
            skills_str+="\033[1;36m${skill}\033[0m "
        else
            skills_str+="\033[2m${skill}\033[0m "
        fi
        ((shown++))
    done

    remaining=$((local_skill_count - shown))
    [ $remaining -gt 0 ] && skills_str+="\033[2m+${remaining}\033[0m"
fi

# MCP servers - read from claude.json mcpServers
mcp_servers=()

if [ -f "$HOME/.claude.json" ]; then
    while IFS= read -r server; do
        [ -n "$server" ] && mcp_servers+=("$server")
    done < <(jq -r '.mcpServers // {} | keys[]' "$HOME/.claude.json" 2>/dev/null)
fi

if [ -f "$cwd/.mcp.json" ]; then
    while IFS= read -r server; do
        [ -n "$server" ] && mcp_servers+=("$server")
    done < <(jq -r '.mcpServers // {} | keys[]' "$cwd/.mcp.json" 2>/dev/null)
fi

mcp_str=""
mcp_count=${#mcp_servers[@]}
if [ "$mcp_count" -gt 0 ]; then
    mcp_str=$'\033[1mmcp:\033[0m '
    shown=0
    for server in "${mcp_servers[@]}"; do
        [ $shown -ge $MAX_MCP_SHOWN ] && break
        mcp_str+="\033[35m${server}\033[0m "
        ((shown++))
    done
    remaining=$((mcp_count - shown))
    [ $remaining -gt 0 ] && mcp_str+="\033[2m+${remaining}\033[0m"
fi

# Commands - available and used
cmds_available=()

for dir in "${CLAUDE_DIR}/commands" "$cwd/.claude/commands"; do
    if [ -d "$dir" ]; then
        while IFS= read -r cmd_file; do
            cmd_name=$(basename "$cmd_file" .md)
            cmds_available+=("$cmd_name")
        done < <(find "$dir" -name "*.md" 2>/dev/null)
    fi
done

# Use pre-computed commands from Python parser
cmds_used_list=" ${T_COMMANDS_USED:-} "

is_cmd_used() {
    [[ "$cmds_used_list" == *" $1 "* ]]
}

cmds_str=""
cmd_count=${#cmds_available[@]}

if [ "$cmd_count" -gt 0 ]; then
    cmds_str=$'\033[1mcmds:\033[0m '
    shown=0

    for cmd in "${cmds_available[@]}"; do
        [ $shown -ge $MAX_COMMANDS_SHOWN ] && break
        if is_cmd_used "$cmd"; then
            cmds_str+="\033[1;36m${cmd}\033[0m "
        else
            cmds_str+="\033[2m${cmd}\033[0m "
        fi
        ((shown++))
    done

    remaining=$((cmd_count - shown))
    [ $remaining -gt 0 ] && cmds_str+="\033[2m+${remaining}\033[0m"
fi

# Assemble domain output (skills, mcp, commands - NO agents for now)
domain_infra=""
[ -n "$skills_str" ] && domain_infra+="$skills_str"
[ -n "$mcp_str" ] && [ -n "$domain_infra" ] && domain_infra+=" │ "
[ -n "$mcp_str" ] && domain_infra+="$mcp_str"
[ -n "$cmds_str" ] && [ -n "$domain_infra" ] && domain_infra+=" │ "
[ -n "$cmds_str" ] && domain_infra+="$cmds_str"
