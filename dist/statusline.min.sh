#!/bin/bash
input=$(cat)
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
BAR_WIDTH=${CLAUDE_METER_BAR_WIDTH:-40}
BAR_STYLE=${CLAUDE_METER_BAR_STYLE:-ascii}
CTX_WARN_THRESHOLD=50
CTX_HIGH_THRESHOLD=70
CTX_CRIT_THRESHOLD=80
CTX_OVERHEAD=${CLAUDE_METER_OVERHEAD:-18000}
CTX_BUFFER=${CLAUDE_METER_BUFFER:-45000}
FOCUS_WINDOW=15
FOCUS_FILE_THRESHOLD=70
FOCUS_DIR_THRESHOLD=50
STRIDE_WINDOW=20
SPARKLINE_STYLE="braille"
STRIDE_ACCEL_HIGH=0.15
STRIDE_ACCEL_LOW=0.05
STRIDE_MIN_RESPONSES=2
REV_THRESHOLD=5
HUMAN_INACTIVITY_GAP=1800
MAX_SKILLS_SHOWN=3
MAX_MCP_SHOWN=5
MAX_COMMANDS_SHOWN=3
SPARKLINE_LENGTH=6
SHOW_RESOURCES=${CLAUDE_METER_RESOURCES:-1}
SHOW_RHYTHM=${CLAUDE_METER_RHYTHM:-1}
SHOW_FOCUS=${CLAUDE_METER_FOCUS:-1}
SHOW_INFRA=${CLAUDE_METER_INFRA:-1}
SHOW_SESSION=${CLAUDE_METER_SESSION:-1}
DOMAIN_ORDER=${CLAUDE_METER_ORDER:-"resources,rhythm,focus,infra,session"}
SLEEP_CACHE="$CACHE_DIR/claude-sleep-times"
SLEEP_CACHE_TTL=300
if [ -f "$SLEEP_CACHE" ]&&[ $(($(date +%s)-$(stat -f %m "$SLEEP_CACHE" 2>/dev/null||echo 0))) -lt $SLEEP_CACHE_TTL ];then
SLEEP_TIMES=$(cat "$SLEEP_CACHE")
else
SLEEP_TIMES=$(pmset -g log 2>/dev/null|perl -ne '
        use Time::Local;
        BEGIN { print "["; $n = 0; }
        if (/^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2}).*Sleep\s+Entering Sleep/) {
            my $ts = timelocal($6, $5, $4, $3, $2-1, $1);
            print "," if $n++;
            print $ts;
        }
        END { print "]"; }
    ' 2>/dev/null)
[ -z "$SLEEP_TIMES" ]&&SLEEP_TIMES="[]"
echo "$SLEEP_TIMES" >"$SLEEP_CACHE" 2>/dev/null
fi
render_sparkline(){
local values="$1"
local style="${2:-$SPARKLINE_STYLE}"
[ -z "$values" ]&&return
echo "$values"|perl -e '
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
repeat_char(){
local char="$1" count="$2"
[ "$count" -le 0 ]&&return
printf "%${count}s"|tr ' ' "$char"
}
fmt_k(){
if [ "$1" -ge 1000 ];then
printf "%dK" "$((($1+500)/1000))"
else
echo "$1"
fi
}
format_secs(){
local secs=$1
local int_secs=${secs%.*}
[ -z "$int_secs" ]&&int_secs=0
if [ "$int_secs" -ge 60 ];then
printf "%dm%.0fs" $((int_secs/60)) "$(echo "$secs - ($int_secs / 60) * 60"|bc)"
else
printf "%.1fs" "$secs"
fi
}
eval "$(echo "$input"|jq -r '
  @sh "model=\(.model.display_name // "unknown")
  cwd=\(.workspace.current_dir // ".")
  sid=\(.session_id // "")
  transcript=\(.transcript_path // "")
  ctx_size=\(.context_window.context_window_size // 200000)
  input_tok=\(.context_window.current_usage.input_tokens // 0)
  cache_read=\(.context_window.current_usage.cache_read_input_tokens // 0)
  cache_create=\(.context_window.current_usage.cache_creation_input_tokens // 0)
  cost=\(.cost.total_cost_usd // 0)"
')"
total_used=$((input_tok+cache_read+cache_create))
effective_max=$ctx_size
if [ "$total_used" -gt 0 ];then
true_pct=$((total_used*100/effective_max))
[ "$true_pct" -gt 100 ]&&true_pct=100
has_usage_data=1
else
true_pct=0
has_usage_data=0
fi
msg_fmt=$(fmt_k "$total_used")
buffer_fmt=$(fmt_k "$CTX_BUFFER")
total_fmt=$(fmt_k "$total_used")
eff_fmt=$(fmt_k "$effective_max")
if [ -f "$transcript" ];then
config_json=$(cat <<EOF
{"stride_window":${STRIDE_WINDOW:-20},"focus_window":${FOCUS_WINDOW:-15},"focus_file_threshold":${FOCUS_FILE_THRESHOLD:-70},"focus_dir_threshold":${FOCUS_DIR_THRESHOLD:-50},"inactivity_gap":${HUMAN_INACTIVITY_GAP:-1800},"sparkline_length":${SPARKLINE_LENGTH:-6},"sleep_times":${SLEEP_TIMES:-[]}}
EOF
)
eval "$(python3 "$CLAUDE_DIR/transcript_parser.py" "$transcript" "$config_json" 2>/dev/null)"
fi
CTX_CACHE_FILE="$CACHE_DIR/claude-ctx-$sid.json"
CTX_CACHE_TTL=3600
ctx_cache_valid=0
if [ -f "$CTX_CACHE_FILE" ];then
cache_age=$(($(date +%s)-$(stat -f %m "$CTX_CACHE_FILE" 2>/dev/null||echo 0)))
[ $cache_age -lt $CTX_CACHE_TTL ]&&ctx_cache_valid=1
fi
if [ "$ctx_cache_valid" -eq 0 ]&&[ -f "$transcript" ];then
ctx_parsed=$(python3 "$CLAUDE_DIR/context_parser.py" "$transcript" 2>/dev/null)
if [ -n "$ctx_parsed" ];then
echo "$ctx_parsed" >"$CTX_CACHE_FILE"
ctx_cache_valid=1
fi
fi
if [ "$ctx_cache_valid" -eq 1 ]&&[ -f "$CTX_CACHE_FILE" ];then
eval "$(jq -r '
        @sh "CTX_SYSTEM_PROMPT=\(.system_prompt // 0)
        CTX_SYSTEM_TOOLS=\(.system_tools // 0)
        CTX_MCP_TOOLS=\(.mcp_tools // 0)
        CTX_MEMORY=\(.memory // 0)
        CTX_SKILLS=\(.skills // 0)"
    ' "$CTX_CACHE_FILE" 2>/dev/null)"
if [ "${CTX_SYSTEM_PROMPT:-0}" -gt 0 ];then
CTX_OVERHEAD=$((CTX_SYSTEM_PROMPT+CTX_SYSTEM_TOOLS))
fi
if [ "${CTX_MCP_TOOLS:-0}" -gt 0 ];then
CTX_MCP=$CTX_MCP_TOOLS
fi
fi
if [ "${has_usage_data:-0}" -eq 0 ];then
domain_resources="\033[2m(context data unavailable)\033[0m"
text_color="\033[37m"
else
if [ $true_pct -lt $CTX_WARN_THRESHOLD ];then
fill_color="48;5;34"
text_color="\033[32m"
elif [ $true_pct -lt $CTX_HIGH_THRESHOLD ];then
fill_color="48;5;220"
text_color="\033[33m"
elif [ $true_pct -lt $CTX_CRIT_THRESHOLD ];then
fill_color="48;5;208"
text_color="\033[38;5;208m"
else
fill_color="48;5;196"
text_color="\033[31m"
fi
msg_width=$((total_used*BAR_WIDTH/effective_max))
pos_buffer_start=$(((effective_max-CTX_BUFFER)*BAR_WIDTH/effective_max))
buffer_width=$((BAR_WIDTH-pos_buffer_start))
remaining=$((pos_buffer_start-msg_width))
[ $msg_width -le 0 ]&&[ $total_used -gt 0 ]&&msg_width=1&&remaining=$((remaining-1))
[ $msg_width -lt 0 ]&&msg_width=0
[ $remaining -lt 0 ]&&remaining=0
fg_color="${fill_color/48;5;/38;5;}"
if [ "$BAR_STYLE" = "blocks" ];then
bar="│"
[ $msg_width -gt 0 ]&&bar+="\033[${fg_color}m$(repeat_char '█' $msg_width)\033[0m"
[ $remaining -gt 0 ]&&bar+="\033[38;5;240m$(repeat_char '·' $remaining)\033[0m"
[ $buffer_width -gt 0 ]&&bar+="\033[38;5;238m$(repeat_char '~' $buffer_width)\033[0m"
bar+="│"
else
bar="┃"
if [ $msg_width -gt 0 ];then
[ $msg_width -gt 1 ]&&bar+="\033[${fg_color}m$(repeat_char '━' $((msg_width-1)))\033[0m"
bar+="\033[${fg_color}m●\033[0m"
fi
[ $remaining -gt 0 ]&&bar+="\033[38;5;240m$(repeat_char '─' $remaining)\033[0m"
[ $remaining -gt 0 ]&&[ $buffer_width -gt 0 ]&&bar+="\033[38;5;240m│\033[0m"
[ $buffer_width -gt 0 ]&&bar+="\033[38;5;238m$(repeat_char '~' $buffer_width)\033[0m"
bar+="┃"
fi
cost_str=$(printf '$%.2f' "$cost")
breakdown="$text_color$total_fmt used\033[0m \033[2m($buffer_fmt reserved)\033[0m"
domain_resources=$(printf "$bar $breakdown │ $msg_fmt / $eff_fmt │ \033[1m%d%%\033[0m │ %s" "$true_pct" "$cost_str")
fi
step_str=""
stride_str=""
mode_str=""
if [ -n "$T_PACE_AVG" ]&&[ "$T_PACE_AVG" != "0" ]&&[ "$T_PACE_AVG" != "0.0" ];then
pace_spark=""
[ -n "$T_PACE_VALS" ]&&pace_spark=$(render_sparkline "$T_PACE_VALS")
step_str=$'\033[1mpace:\033[0m '"$(format_secs "$T_PACE_AVG")"
[ -n "$pace_spark" ]&&step_str+=" $pace_spark"
fi
user_total=${T_USER_TOTAL:-0}
claude_total=${T_CLAUDE_TOTAL:-0}
user_recent=${T_USER_RECENT:-0}
claude_recent=${T_CLAUDE_RECENT:-0}
if [ "$user_total" -gt 0 ]&&[ "$claude_total" -gt 0 ];then
stride=$(echo "1:1 1:2 1:3 1:4 1:5 1:6 1:7 1:8 2:3 3:4 4:5 5:6 5:8 3:8 2:5 3:5 1:10 1:12 1:15 1:20"|tr ' ' '\n'|awk -v u="$user_total" -v c="$claude_total" '
        BEGIN { actual = u / c; best_diff = 999 }
        { split($0, m, ":"); ratio = m[1] / m[2]
          diff = (actual - ratio) > 0 ? (actual - ratio) : (ratio - actual)
          if (diff < best_diff) { best_diff = diff; best = $0 } }
        END { print best }
    ')
accel="·"
if [ "$user_recent" -gt 0 ]&&[ "$claude_recent" -gt "$STRIDE_MIN_RESPONSES" ];then
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
stride_str="\033[1mstride:\033[0m $stride $accel"
else
stride_str="\033[1mstride:\033[0m —"
fi
if [ -n "$T_MODE" ];then
case "$T_MODE" in
idle)mode_str="\033[2mmode: idle\033[0m"
;;
stuck)mode_str="\033[1mmode:\033[0m \033[31mstuck\033[0m"
;;
*)mode_str="\033[1mmode:\033[0m $T_MODE"
esac
fi
domain_rhythm=""
[ -n "$stride_str" ]&&domain_rhythm+="$stride_str"
[ -n "$step_str" ]&&[ -n "$domain_rhythm" ]&&domain_rhythm+=" │ "
[ -n "$step_str" ]&&domain_rhythm+="$step_str"
[ -n "$mode_str" ]&&[ -n "$domain_rhythm" ]&&domain_rhythm+=" │ "
[ -n "$mode_str" ]&&domain_rhythm+="$mode_str"
focus_str=""
rev_str=""
prev_type="${T_FOCUS_PREV_TYPE:-}"
prev_label="${T_FOCUS_PREV_LABEL:-}"
curr_type="${T_FOCUS_CURR_TYPE:-}"
curr_label="${T_FOCUS_CURR_LABEL:-}"
top_edit_file="${T_TOP_EDIT_FILE:-}"
top_edit_count="${T_TOP_EDIT_COUNT:-0}"
if [ -n "$curr_type" ]&&[ "$curr_type" != "none" ];then
if [ -z "$prev_type" ]||[ "$prev_type" == "none" ]||{ [ "$prev_type" == "$curr_type" ]&&[ "$prev_label" == "$curr_label" ];};then
focus_str="\033[1mfocus:\033[0m \033[2m$curr_type\033[0m $curr_label"
else
focus_str="\033[1mfocus:\033[0m \033[2m$prev_type\033[0m $prev_label → \033[2m$curr_type\033[0m $curr_label"
fi
fi
if [ "$top_edit_count" -ge "$REV_THRESHOLD" ]&&[ -n "$top_edit_file" ];then
rev_str="\033[1medits:\033[0m $top_edit_file ($top_edit_count)"
fi
domain_focus=""
[ -n "$focus_str" ]&&domain_focus+="$focus_str"
[ -n "$rev_str" ]&&[ -n "$domain_focus" ]&&domain_focus+=" │ "
[ -n "$rev_str" ]&&domain_focus+="$rev_str"
local_skills=()
if [ -d "$cwd/.claude/skills" ];then
while IFS= read -r skill_file;do
skill_name=$(basename "$(dirname "$skill_file")")
local_skills+=("$skill_name")
done < <(find "$cwd/.claude/skills" -name "SKILL.md" 2>/dev/null)
fi
skills_loaded_list=" ${T_SKILLS_LOADED:-} "
is_loaded(){
[[ $skills_loaded_list == *" $1 "* ]]
}
skills_str=""
local_skill_count=${#local_skills[@]}
if [ "$local_skill_count" -gt 0 ];then
skills_str=$'\033[1mskills:\033[0m '
shown=0
for skill in "${local_skills[@]}";do
[ $shown -ge $MAX_SKILLS_SHOWN ]&&break
if is_loaded "$skill";then
skills_str+="\033[1;36m$skill\033[0m "
else
skills_str+="\033[2m$skill\033[0m "
fi
((shown++))
done
remaining=$((local_skill_count-shown))
[ $remaining -gt 0 ]&&skills_str+="\033[2m+$remaining\033[0m"
fi
mcp_servers=()
if [ -f "$HOME/.claude.json" ];then
while IFS= read -r server;do
[ -n "$server" ]&&mcp_servers+=("$server")
done < <(jq -r '.mcpServers // {} | keys[]' "$HOME/.claude.json" 2>/dev/null)
fi
if [ -f "$cwd/.mcp.json" ];then
while IFS= read -r server;do
[ -n "$server" ]&&mcp_servers+=("$server")
done < <(jq -r '.mcpServers // {} | keys[]' "$cwd/.mcp.json" 2>/dev/null)
fi
mcp_str=""
mcp_count=${#mcp_servers[@]}
if [ "$mcp_count" -gt 0 ];then
mcp_str=$'\033[1mmcp:\033[0m '
shown=0
for server in "${mcp_servers[@]}";do
[ $shown -ge $MAX_MCP_SHOWN ]&&break
mcp_str+="\033[35m$server\033[0m "
((shown++))
done
remaining=$((mcp_count-shown))
[ $remaining -gt 0 ]&&mcp_str+="\033[2m+$remaining\033[0m"
fi
cmds_available=()
for dir in "$CLAUDE_DIR/commands" "$cwd/.claude/commands";do
if [ -d "$dir" ];then
while IFS= read -r cmd_file;do
cmd_name=$(basename "$cmd_file" .md)
cmds_available+=("$cmd_name")
done < <(find "$dir" -name "*.md" 2>/dev/null)
fi
done
cmds_used_list=" ${T_COMMANDS_USED:-} "
is_cmd_used(){
[[ $cmds_used_list == *" $1 "* ]]
}
cmds_str=""
cmd_count=${#cmds_available[@]}
if [ "$cmd_count" -gt 0 ];then
cmds_str=$'\033[1mcmds:\033[0m '
shown=0
for cmd in "${cmds_available[@]}";do
[ $shown -ge $MAX_COMMANDS_SHOWN ]&&break
if is_cmd_used "$cmd";then
cmds_str+="\033[1;36m$cmd\033[0m "
else
cmds_str+="\033[2m$cmd\033[0m "
fi
((shown++))
done
remaining=$((cmd_count-shown))
[ $remaining -gt 0 ]&&cmds_str+="\033[2m+$remaining\033[0m"
fi
domain_infra=""
[ -n "$skills_str" ]&&domain_infra+="$skills_str"
[ -n "$mcp_str" ]&&[ -n "$domain_infra" ]&&domain_infra+=" │ "
[ -n "$mcp_str" ]&&domain_infra+="$mcp_str"
[ -n "$cmds_str" ]&&[ -n "$domain_infra" ]&&domain_infra+=" │ "
[ -n "$cmds_str" ]&&domain_infra+="$cmds_str"
cd "$cwd" 2>/dev/null||cd /
if git rev-parse --git-dir >/dev/null 2>&1;then
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
if [ -n "$upstream" ];then
ahead=$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null||echo 0)
behind=$(git rev-list --count 'HEAD..@{upstream}' 2>/dev/null||echo 0)
sync=""
[ "$ahead" -gt 0 ]&&sync+="↑$ahead"
[ "$behind" -gt 0 ]&&sync+="↓$behind"
[ -z "$sync" ]&&sync="✓"
else
sync="○"
fi
diff_stats=$(git diff --numstat HEAD 2>/dev/null|awk '{a+=$1; d+=$2} END {print a+0, d+0}')
lines_add=$(echo "$diff_stats"|cut -d' ' -f1)
lines_del=$(echo "$diff_stats"|cut -d' ' -f2)
last_commit=$(git log -1 --format=%ct 2>/dev/null)
if [ -n "$last_commit" ];then
now=$(date +%s)
diff=$((now-last_commit))
if [ $diff -lt 60 ];then
commit_ago="${diff}s"
elif [ $diff -lt 3600 ];then
commit_ago="$((diff/60))m"
elif [ $diff -lt 86400 ];then
commit_ago="$((diff/3600))h"
else
commit_ago="$((diff/86400))d"
fi
else
commit_ago="-"
fi
if [ "$lines_add" -eq 0 ]&&[ "$lines_del" -eq 0 ];then
git_str="\033[2m$branch\033[0m $sync \033[2m$commit_ago\033[0m"
else
git_str="\033[2m$branch\033[0m \033[32m+$lines_add\033[0m/\033[31m-$lines_del\033[0m $sync \033[2m$commit_ago\033[0m"
fi
else
git_str="\033[2m-\033[0m"
fi
sf="$CACHE_DIR/claude-session-$sid"
if [ ! -f "$sf" ];then
date +%s >"$sf"
fi
start=$(cat "$sf" 2>/dev/null)
if ! [[ $start =~ ^[0-9]+$ ]];then
start=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${start%%+*}" "+%s" 2>/dev/null||date +%s)
fi
inactive_secs=${T_INACTIVE_SECS:-0}
dur=$(($(date +%s)-start-inactive_secs))
[ $dur -lt 0 ]&&dur=0
h=$((dur/3600))
m=$(((dur%3600)/60))
s=$((dur%60))
if [ $h -gt 0 ];then
dur_str=$'\033[1msess:\033[0m '$(printf "%dh%02dm" $h $m)
elif [ $m -gt 0 ];then
dur_str=$'\033[1msess:\033[0m '$(printf "%dm%02ds" $m $s)
else
dur_str=$'\033[1msess:\033[0m '$(printf "%ds" $s)
fi
domain_session="$git_str │ \033[36m$model\033[0m │ $dur_str"
domains=()
IFS=',' read -ra order <<<"$DOMAIN_ORDER"
for d in "${order[@]}";do
case "$d" in
resources)[ "$SHOW_RESOURCES" = "1" ]&&[ -n "$domain_resources" ]&&domains+=("$domain_resources");;
rhythm)[ "$SHOW_RHYTHM" = "1" ]&&[ -n "$domain_rhythm" ]&&domains+=("$domain_rhythm");;
focus)[ "$SHOW_FOCUS" = "1" ]&&[ -n "$domain_focus" ]&&domains+=("$domain_focus");;
infra)[ "$SHOW_INFRA" = "1" ]&&[ -n "$domain_infra" ]&&domains+=("$domain_infra");;
session)[ "$SHOW_SESSION" = "1" ]&&[ -n "$domain_session" ]&&domains+=("$domain_session")
esac
done
count=${#domains[@]}
for i in "${!domains[@]}";do
if [ $((i+1)) -eq "$count" ];then
printf "\033[2m└─\033[0m %b\n" "${domains[$i]}"
else
printf "\033[2m├─\033[0m %b\n" "${domains[$i]}"
fi
done
