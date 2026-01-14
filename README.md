# Claude Meter

Custom statusline for Claude Code CLI. Displays context usage, session metrics, and workflow state.

```
┃━━━━━━━━━━━━━━●──────────────────│~~~~~~~~┃ 65K used (45K reserved) │ 50K / 155K │ 32% │ $0.42
stride: 1:4 ‹ │ pace: ⣤⣶⣿⣶⣤⣀ 8.2s │ coding
focus: → config.yml │ edits: build.sh (3)
skills: sample │ mcp: context7 exa │ cmds: commit
main +12/-3 ✓ 5m │ opus │ sess: 12m34s
```

## Features

- **Progress bar** - Visual context window usage with color thresholds
- **Resource tracking** - Token counts, costs, context percentage
- **Rhythm metrics** - Stride ratio (user:claude) with acceleration arrows (« ‹ · › »), pace sparkline, mode detection
- **Focus tracking** - Current file/directory concentration, edit counts
- **Infrastructure** - Skills loaded, MCP servers connected, slash commands used
- **Session info** - Git branch, model name, active session duration

## Requirements

- macOS (uses `pmset` for sleep detection, `stat -f` syntax)
- [task](https://taskfile.dev/) - Task runner
- [jq](https://jqlang.github.io/jq/) - JSON processing
- Python 3.9+
- Homebrew (for installing shellcheck, shfmt, yq)

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/claude-meter.git
cd claude-meter

# Install dependencies
task deps

# Build and link to ~/.claude
task link
```

This creates:
- `~/.claude/statusline.sh` - symlink to the built script
- `~/.claude/transcript_parser.py` - Python transcript parser
- `~/.claude/context_parser.py` - Python context parser

## Configuration

Edit `config.yml` to customize:

```yaml
options:
  bar_width: 40           # Progress bar width
  bar_style: ascii        # ascii | blocks
  warn_threshold: 50      # Yellow at 50%
  high_threshold: 70      # Orange at 70%
  crit_threshold: 80      # Red at 80%
  ctx_overhead: 18000     # System prompt tokens
  ctx_buffer: 45000       # Autocompact reserve

domains:
  - resources             # Order matters for display
  - rhythm
  - focus
  - infra
  - session
```

After editing, run `task build && task link` to apply changes.

## Runtime Configuration

Toggle domains at runtime via environment variables:

```bash
export CLAUDE_METER_RESOURCES=0  # Hide resources domain
export CLAUDE_METER_RHYTHM=1     # Show rhythm domain (default)
export CLAUDE_METER_FOCUS=1      # Show focus domain (default)
export CLAUDE_METER_INFRA=1      # Show infra domain (default)
export CLAUDE_METER_SESSION=1    # Show session domain (default)
```

## Development

```bash
task lint      # Run shellcheck on source files
task fmt       # Format source files with shfmt
task build     # Assemble and minify
task dev:test  # Test with sample JSON input
task clean     # Remove build artifacts
```

## How It Works

Claude Code pipes JSON to the statusline script on each update:
```json
{"model": {...}, "session_id": "...", "transcript_path": "...", "context_window": {...}, "cost": 0.42}
```

The script:
1. Parses the JSON input
2. Reads the transcript file for detailed metrics
3. Caches expensive computations (context parsing, sleep times)
4. Outputs formatted ANSI text for display

## Progress Bar

```
┃━━━━━━━━━━━━━━●──────────────────│~~~~~~~~┃
 used (colored)                     buffer (gray)
```

- **Used segment**: Context tokens consumed (● marks current position)
- **Buffer segment**: Autocompact reserve (~45K tokens, shown as `~`)
- **Colors**: green <50%, yellow 50-70%, orange 70-80%, red >80%

## Domains

1. **resources** - Progress bar, token counts, cost
2. **rhythm** - Stride ratio (user:claude messages), pace sparkline, mode (exploring/coding/shipping/etc)
3. **focus** - Current file/dir concentration, edit revision counts
4. **infra** - Local skills, MCP servers, slash commands used
5. **session** - Git branch/status, model name, session duration

## Adding a New Domain

1. Create `src/domains/mydomain.sh`:
   ```bash
   # shellcheck shell=bash
   # shellcheck disable=SC2154,SC2034
   # Provides: domain_mydomain
   # Requires: transcript (from core/input)

   domain_mydomain="my output"
   ```
2. Add to `config.yml` domains list
3. Add case to `src/output/99-assemble.sh`
4. Run `task build && task link`

## Architecture

See [CLAUDE.md](CLAUDE.md) for detailed architecture documentation.

## License

MIT License - see [LICENSE](LICENSE) for details.
