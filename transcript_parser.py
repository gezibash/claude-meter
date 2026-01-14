#!/usr/bin/env python3
"""
Consolidated transcript parser for claude-meter.
Single-pass extraction of all metrics - replaces multiple awk/jq/grep calls.

Usage: python3 transcript_parser.py <transcript_path> [config_json]
Output: Shell-evaluable variable assignments (T_* prefix)

Extracts:
  - Timing: inactive_secs, pace_avg, pace_vals
  - Stride: user/claude counts (total + recent window)
  - Mode: tool distribution-based mode detection
  - Focus: file/dir concentration, transitions, edit counts
  - Infra: skills loaded, commands used
"""

import sys
import json
from datetime import datetime, timezone
from collections import defaultdict
from pathlib import Path

# Defaults (overridden by config_json argument)
CONFIG = {
    "stride_window": 20,
    "focus_window": 15,
    "focus_file_threshold": 70,
    "focus_dir_threshold": 50,
    "inactivity_gap": 1800,
    "sparkline_length": 6,
    "sleep_times": [],
}

# Tool categories (from statusline_mode.py)
READ_TOOLS = {"Read", "Glob", "Grep", "WebFetch", "WebSearch"}
WRITE_TOOLS = {"Edit", "Write"}
AGENT_TOOLS = {"Task"}

BUILD_PATTERNS = [
    "go build",
    "npm run build",
    "npm build",
    "yarn build",
    "cargo build",
    "make",
    "cmake",
    "tsc",
    "webpack",
    "vite build",
    "docker build",
    "gradle build",
    "mvn compile",
    "mvn package",
]
TEST_PATTERNS = [
    "go test",
    "npm test",
    "npm run test",
    "yarn test",
    "pytest",
    "python -m pytest",
    "jest",
    "vitest",
    "cargo test",
    "make test",
    "mocha",
    "rspec",
    "gradle test",
    "mvn test",
]

# Mode thresholds
RATIO_DOMINANT = 0.6
RATIO_COMMAND = 0.3
WINDOW_SHORT = 3
WINDOW_MID = 10
IDLE_THRESHOLD = 600
STUCK_REV_THRESHOLD = 10
PACE_SLOW = 15


def parse_timestamp(ts: str) -> float | None:
    """Parse ISO timestamp to Unix epoch."""
    if not ts:
        return None
    try:
        # Handle both Z and +00:00 formats
        ts = ts.replace("Z", "+00:00")
        dt = datetime.fromisoformat(ts)
        return dt.timestamp()
    except (ValueError, TypeError):
        return None


def classify_bash_command(cmd: str) -> str | None:
    """Classify a bash command as 'build', 'test', or None."""
    cmd_lower = cmd.lower()
    for pattern in BUILD_PATTERNS:
        if pattern in cmd_lower:
            return "build"
    for pattern in TEST_PATTERNS:
        if pattern in cmd_lower:
            return "test"
    return None


class TranscriptParser:
    def __init__(self, config: dict):
        self.config = config
        self.reset()

    def reset(self):
        """Reset state (called at compact_boundary)."""
        # Timing
        self.timestamps: list[float] = []
        self.user_timestamps: list[float] = []

        # Stride
        self.stride_window: list[str] = []  # 'u' or 'c'

        # Tool operations (for mode detection)
        self.tool_ops: list[dict] = []

        # Focus
        self.focus_window: list[tuple[str, str]] = []  # (dir, file)
        self.edits: dict[str, int] = defaultdict(int)

        # Infra
        self.skills_loaded: set[str] = set()
        self.commands_used: set[str] = set()

    def process_entry(self, entry: dict):
        """Process a single transcript entry."""
        ts_str = entry.get("timestamp")
        ts = parse_timestamp(ts_str)
        etype = entry.get("type")
        subtype = entry.get("subtype")

        # Compact boundary - reset all state
        if subtype == "compact_boundary":
            self.reset()
            return

        # Track all timestamps
        if ts is not None:
            self.timestamps.append(ts)

        # User messages (external, not tool results, not compact summary)
        if etype == "user":
            user_type = entry.get("userType")
            is_tool_result = entry.get("toolUseResult") is not None
            is_compact = entry.get("isCompactSummary", False)

            if user_type == "external" and not is_tool_result and not is_compact:
                if ts is not None:
                    self.user_timestamps.append(ts)
                self.stride_window.append("u")

        # Assistant messages with tool calls
        elif etype == "assistant":
            msg = entry.get("message", {})
            content = msg.get("content", [])

            has_text = False
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict):
                        if item.get("type") == "tool_use":
                            self._process_tool_use(item, ts)
                        elif item.get("type") == "text":
                            has_text = True

            if has_text:
                self.stride_window.append("c")

    def _process_tool_use(self, item: dict, ts: float | None):
        """Process a tool_use item."""
        name = item.get("name", "")
        inp = item.get("input", {})

        # Record for mode detection
        self.tool_ops.append({"name": name, "timestamp": ts, "input": inp})

        # File operations for focus tracking
        if name in ("Read", "Edit", "Write"):
            path = inp.get("file_path", "")
            if path:
                parts = Path(path).parts
                dir_name = parts[-2] if len(parts) >= 2 else "."
                file_name = parts[-1] if parts else ""

                self.focus_window.append((dir_name, file_name))

                if name in ("Edit", "Write"):
                    self.edits[file_name] += 1

        # Skills
        elif name == "Skill":
            skill = inp.get("skill", "")
            if skill:
                self.skills_loaded.add(skill)

        # Slash commands
        elif name == "SlashCommand":
            cmd = inp.get("command", "")
            if cmd:
                cmd = cmd.lstrip("/").split()[0]
                self.commands_used.add(cmd)

        # Bash commands for build/test detection (already captured in tool_ops)

    def compute_metrics(self) -> dict:
        """Compute all derived metrics."""
        return {
            **self._compute_timing(),
            **self._compute_stride(),
            **self._compute_mode(),
            **self._compute_focus(),
            **self._compute_infra(),
        }

    def _compute_timing(self) -> dict:
        """Compute timing metrics: inactive_secs, pace_avg, pace_vals."""
        inactive_secs = 0
        pace_gaps: list[float] = []
        sleep_times = set(self.config.get("sleep_times", []))
        inactivity_gap = self.config.get("inactivity_gap", 1800)

        for i in range(1, len(self.timestamps)):
            t1, t2 = self.timestamps[i - 1], self.timestamps[i]
            gap = t2 - t1

            if gap <= 0:
                continue

            # Check for sleep during this gap
            has_sleep = any(t1 < st < t2 for st in sleep_times)

            if has_sleep or gap >= inactivity_gap:
                inactive_secs += gap
            elif 0 < gap < 1800:
                pace_gaps.append(gap)

        # Compute pace average
        pace_avg = sum(pace_gaps) / len(pace_gaps) if pace_gaps else 0

        # Compute pace sparkline values (segment into chunks)
        pace_vals = ""
        segments = self.config.get("sparkline_length", 6)
        if len(pace_gaps) >= segments * 2:
            chunk_size = len(pace_gaps) // segments
            vals = []
            for i in range(segments):
                chunk = pace_gaps[i * chunk_size : (i + 1) * chunk_size]
                if chunk:
                    vals.append(f"{sum(chunk) / len(chunk):.1f}")
            pace_vals = ",".join(vals)

        return {
            "T_INACTIVE_SECS": int(inactive_secs),
            "T_PACE_AVG": round(pace_avg, 1),
            "T_PACE_VALS": pace_vals,
        }

    def _compute_stride(self) -> dict:
        """Compute stride metrics: user/claude text counts."""
        window = self.config.get("stride_window", 20)
        recent = (
            self.stride_window[-window:]
            if len(self.stride_window) > window
            else self.stride_window
        )

        return {
            "T_USER_TOTAL": sum(1 for x in self.stride_window if x == "u"),
            "T_CLAUDE_TOTAL": sum(1 for x in self.stride_window if x == "c"),
            "T_USER_RECENT": sum(1 for x in recent if x == "u"),
            "T_CLAUDE_RECENT": sum(1 for x in recent if x == "c"),
        }

    def _compute_mode(self) -> dict:
        """Compute mode detection (from statusline_mode.py logic)."""
        ops = self.tool_ops

        # Check idle
        if ops and ops[-1].get("timestamp"):
            last_ts = ops[-1]["timestamp"]
            now = datetime.now(timezone.utc).timestamp()
            if now - last_ts > IDLE_THRESHOLD:
                return {"T_MODE": "idle"}

        # Check stuck (many edits to same file + slow pace)
        if self.edits:
            max_edits = max(self.edits.values())
            if max_edits >= STUCK_REV_THRESHOLD:
                # Calculate recent pace
                recent_ops = ops[-WINDOW_MID:] if len(ops) >= WINDOW_MID else ops
                if len(recent_ops) >= 2:
                    gaps = []
                    for i in range(1, len(recent_ops)):
                        t1 = recent_ops[i - 1].get("timestamp")
                        t2 = recent_ops[i].get("timestamp")
                        if t1 and t2:
                            gap = t2 - t1
                            if 0 < gap < 1800:
                                gaps.append(gap)
                    if gaps and sum(gaps) / len(gaps) > PACE_SLOW:
                        return {"T_MODE": "stuck"}

        # Get modes for short and mid windows
        short_ops = ops[-WINDOW_SHORT:] if len(ops) >= WINDOW_SHORT else ops
        mid_ops = ops[-WINDOW_MID:] if len(ops) >= WINDOW_MID else ops

        short_mode = self._detect_mode_for_window(short_ops)
        mid_mode = self._detect_mode_for_window(mid_ops)

        # Format output
        if short_mode != mid_mode:
            mode = f"{mid_mode} → {short_mode}"
        else:
            mode = mid_mode

        return {"T_MODE": mode}

    def _detect_mode_for_window(self, ops: list) -> str:
        """Detect mode based on tool distribution in a window."""
        if not ops:
            return "talking"

        reads = writes = builds = tests = agents = 0

        for op in ops:
            name = op["name"]

            if name in READ_TOOLS:
                reads += 1
            elif name in WRITE_TOOLS:
                writes += 1
            elif name == "Bash":
                cmd = op["input"].get("command", "")
                cmd_type = classify_bash_command(cmd)
                if cmd_type == "build":
                    builds += 1
                elif cmd_type == "test":
                    tests += 1
            elif name in AGENT_TOOLS:
                agents += 1

        total = reads + writes + builds + tests + agents

        if total == 0:
            return "talking"

        # Priority: special command modes first
        if builds / total > RATIO_COMMAND:
            return "building"
        if tests / total > RATIO_COMMAND:
            return "testing"
        if agents / total > RATIO_COMMAND:
            return "delegating"

        # Distribution-based modes
        read_ratio = reads / total
        write_ratio = writes / total

        if write_ratio > RATIO_DOMINANT:
            return "shipping"
        if read_ratio > RATIO_DOMINANT:
            return "exploring"

        return "coding"

    def _compute_focus(self) -> dict:
        """Compute focus tracking: file/dir concentration."""
        window = self.config.get("focus_window", 15)
        file_thresh = self.config.get("focus_file_threshold", 70)
        dir_thresh = self.config.get("focus_dir_threshold", 50)

        total = len(self.focus_window)
        curr_start = max(0, total - window)
        prev_start = max(0, total - window * 2)
        prev_end = curr_start

        curr_win = self.focus_window[curr_start:total]
        prev_win = self.focus_window[prev_start:prev_end]

        def get_state(win: list) -> tuple[str, str]:
            if not win:
                return ("none", "")

            dir_counts: dict[str, int] = defaultdict(int)
            file_counts: dict[str, int] = defaultdict(int)

            for d, f in win:
                if d and f:
                    dir_counts[d] += 1
                    file_counts[f] += 1

            if not file_counts:
                return ("none", "")

            top_dir = (
                max(dir_counts.items(), key=lambda x: x[1]) if dir_counts else ("", 0)
            )
            top_file = (
                max(file_counts.items(), key=lambda x: x[1]) if file_counts else ("", 0)
            )
            unique_files = len(file_counts)

            n = len(win)
            file_conc = int(top_file[1] * 100 / n)
            dir_conc = int(top_dir[1] * 100 / n)

            if file_conc >= file_thresh:
                return ("file", top_file[0])
            elif dir_conc >= dir_thresh:
                return ("dir", top_dir[0] + "/")
            else:
                return ("repo", f"({unique_files})")

        curr_state = get_state(curr_win)
        prev_state = get_state(prev_win)

        # Top edit file
        top_edit = (
            max(self.edits.items(), key=lambda x: x[1]) if self.edits else ("", 0)
        )

        return {
            "T_FOCUS_PREV_TYPE": prev_state[0],
            "T_FOCUS_PREV_LABEL": prev_state[1],
            "T_FOCUS_CURR_TYPE": curr_state[0],
            "T_FOCUS_CURR_LABEL": curr_state[1],
            "T_TOP_EDIT_FILE": top_edit[0],
            "T_TOP_EDIT_COUNT": top_edit[1],
        }

    def _compute_infra(self) -> dict:
        """Compute infra metrics: skills, commands."""
        return {
            "T_SKILLS_LOADED": " ".join(sorted(self.skills_loaded)),
            "T_COMMANDS_USED": " ".join(sorted(self.commands_used)),
        }


def shell_quote(s: str) -> str:
    """Quote a string for shell eval (escape single quotes)."""
    return s.replace("'", "'\\''")


def main():
    if len(sys.argv) < 2:
        print("# No transcript path provided", file=sys.stderr)
        sys.exit(0)

    transcript_path = sys.argv[1]

    # Parse config if provided
    config = CONFIG.copy()
    if len(sys.argv) > 2:
        try:
            config.update(json.loads(sys.argv[2]))
        except json.JSONDecodeError:
            pass

    # Check file exists
    if not Path(transcript_path).exists():
        print("# Transcript not found", file=sys.stderr)
        sys.exit(0)

    parser = TranscriptParser(config)

    try:
        with open(transcript_path) as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    parser.process_entry(entry)
                except json.JSONDecodeError:
                    pass

        metrics = parser.compute_metrics()

        # Output as shell assignments
        for key, value in sorted(metrics.items()):
            if isinstance(value, str):
                safe = shell_quote(value)
                print(f"{key}='{safe}'")
            elif isinstance(value, (int, float)):
                print(f"{key}={value}")

    except Exception as e:
        print(f"# Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
