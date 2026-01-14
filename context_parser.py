#!/usr/bin/env python3
"""Parse /context output from Claude transcript and output JSON."""

import json
import re
import sys
from datetime import datetime, timezone


def strip_ansi(text: str) -> str:
    """Remove ANSI escape codes (handles both \x1b and unicode escapes)."""
    # Handle unicode escapes like \u001b and literal \n
    try:
        text = text.encode("utf-8").decode("unicode_escape", errors="replace")
    except Exception:
        pass
    # Convert literal \n to actual newlines
    text = text.replace("\\n", "\n")
    # Remove ANSI escape sequences
    ansi_pattern = re.compile(r"\x1b\[[0-9;]*m|\x1b\[\?[0-9]+[hl]|\[[\d;]*m")
    return ansi_pattern.sub("", text)


def parse_tokens(text: str, pattern: str) -> int:
    """Extract token count from pattern like 'System prompt: 3.1k tokens'."""
    match = re.search(pattern + r":\s*([\d.]+)(k)?\s*tokens", text, re.IGNORECASE)
    if match:
        value = float(match.group(1))
        if match.group(2):  # has 'k' suffix
            value *= 1000
        return int(value)
    return 0


def parse_context_output(transcript_path: str) -> dict:
    """Parse the last /context output from transcript."""
    result = {
        "system_prompt": 0,
        "system_tools": 0,
        "mcp_tools": 0,
        "memory": 0,
        "skills": 0,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    try:
        with open(transcript_path, "r") as f:
            content = f.read()
    except Exception:
        return result

    # In JSONL, the tags might be escaped or unescaped - try both
    # Also handle escaped newlines in JSON strings
    pattern = r"<local-command-stdout>(.*?)</local-command-stdout>"
    matches = re.findall(pattern, content, re.DOTALL)

    # Also try with escaped tags (inside JSON strings)
    if not matches:
        pattern = r"<local-command-stdout>(.*?)<\\/local-command-stdout>"
        matches = re.findall(pattern, content, re.DOTALL)

    # Find the last one with Context Usage
    context_block = None
    for match in reversed(matches):
        if "Context Usage" in match:
            context_block = match
            break

    if not context_block:
        return result

    # Strip ANSI codes
    clean = strip_ansi(context_block)

    # Parse main token values
    result["system_prompt"] = parse_tokens(clean, "System prompt")
    result["system_tools"] = parse_tokens(clean, "System tools")
    result["mcp_tools"] = parse_tokens(clean, "MCP tools")
    result["memory"] = parse_tokens(clean, "Memory files")

    # Sum individual skills (lines like "└ sample-skill: 70 tokens")
    skills_section = False
    skills_total = 0
    for line in clean.split("\n"):
        if "Skills and slash commands" in line:
            skills_section = True
            continue
        if skills_section:
            # Match lines like "└ skill-name: 70 tokens"
            match = re.search(r":\s*(\d+)\s*tokens", line)
            if match:
                skills_total += int(match.group(1))

    result["skills"] = skills_total

    return result


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)

    result = parse_context_output(sys.argv[1])

    # Only output if we found actual values
    if result["system_prompt"] > 0 or result["mcp_tools"] > 0:
        print(json.dumps(result))
