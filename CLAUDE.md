# claude-meter

Custom statusline for Claude Code CLI. Displays context usage, session metrics, and workflow state.

## Architecture

Modular build system - components are assembled at build time from `config.yml`.

```
claude-meter/
├── config.yml              # Enabled domains + options
├── build.sh                # Reads YAML, assembles components
├── src/
│   ├── core/               # Always included (sorted order)
│   │   ├── 00-header.sh    # Shebang + input capture
│   │   ├── 05-config.sh    # Generated from config.yml
│   │   ├── 10-constants.sh # Hardcoded constants
│   │   ├── 20-helpers.sh   # fmt_k, sparkline, format_secs
│   │   ├── 30-input.sh     # JSON parsing + token metrics
│   │   ├── 32-transcript-parse.sh  # Transcript parsing via Python
│   │   └── 35-context-cache.sh     # Context cache management
│   ├── domains/            # Included per config.yml
│   │   ├── resources.sh    # Progress bar + tokens
│   │   ├── rhythm.sh       # Stride, pace, mode
│   │   ├── focus.sh        # Focus tracking
│   │   ├── infra.sh        # Skills, MCP, commands
│   │   └── session.sh      # Git, model, duration
│   └── output/
│       └── 99-assemble.sh  # Domain assembly + tree output
├── dist/
│   └── statusline.min.sh   # Final minified output
├── transcript_parser.py    # Python helper for transcript parsing
└── context_parser.py       # Python helper for context extraction
```

## Configuration

Edit `config.yml` to customize:

```yaml
options:
  bar_width: 40
  bar_style: ascii          # ascii | blocks
  warn_threshold: 50        # Yellow at 50%
  high_threshold: 70        # Orange at 70%
  crit_threshold: 80        # Red at 80%
  ctx_overhead: 18000       # System prompt tokens
  ctx_buffer: 45000         # Autocompact reserve

domains:
  - resources               # Order matters
  - rhythm
  - focus
  - infra
  - session
```

## Build Commands

```bash
task deps      # Install shellcheck, shfmt, yq
task build     # Generate config, assemble, minify
task link      # Symlink dist/ to ~/.claude/statusline.sh
task lint      # Run shellcheck on src/
task fmt       # Format src/ with shfmt
task clean     # Remove dist/ and generated config
task dev:test  # Test with sample JSON input
```

## How It Works

Claude Code pipes JSON to the statusline script on each update:
```
{model, session_id, transcript_path, context_window, cost, workspace}
```

The script parses this + reads the transcript file to compute metrics.

## Progress Bar

```
┃━━━━━━━━━━━━━━●──────────────────│~~~~~~~~┃
 used (colored by %)               buffer (gray)
```

- **used**: Context tokens consumed (● = current position)
- **buffer**: Autocompact reserve (~45K, shown as `~~~`)
- Colors: green <50%, yellow 50-70%, orange 70-80%, red >80%

## Output Domains

Toggle via env vars (`CLAUDE_METER_*`) at runtime:

1. **resources**: Progress bar, token counts, cost
2. **rhythm**: Stride ratio, pace, mode
3. **focus**: Current file/dir focus, transitions
4. **infra**: Skills, MCP servers, commands
5. **session**: Git branch, model, duration

## Adding Features

1. Edit component in `src/domains/` or `src/core/`
2. Run `task build && task link` to deploy
3. Changes take effect on next Claude update

## Adding a New Domain

1. Create `src/domains/mydomain.sh`:
   ```bash
   # shellcheck shell=bash
   # shellcheck disable=SC2154,SC2034
   # Provides: domain_mydomain
   # Requires: transcript (from core/input)

   domain_mydomain="..."
   ```
2. Add to `config.yml` domains list
3. Add case to `src/output/99-assemble.sh`
4. Run `task build`

## Debugging

```bash
# Test assembled script
task dev:test

# Test with custom JSON
echo '{"model":{"display_name":"opus"},...}' | dist/statusline.sh

# Check assembled (non-minified) output
cat dist/statusline.sh
```
