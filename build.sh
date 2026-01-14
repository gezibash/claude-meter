#!/bin/bash
# Build script for claude-meter statusline
# Reads config.yml, generates config, and assembles components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
DIST_DIR="$SCRIPT_DIR/dist"
CONFIG="$SCRIPT_DIR/config.yml"
CONFIG_OUT="$SRC_DIR/core/05-config.sh"
OUTPUT="$DIST_DIR/statusline.sh"
OUTPUT_MIN="$DIST_DIR/statusline.min.sh"

# ============================================================================
# YAML parsing (requires yq)
# ============================================================================
parse_yaml() {
    if ! command -v yq &>/dev/null; then
        echo "Error: yq is required. Install with: brew install yq" >&2
        exit 1
    fi

    # Parse options with defaults
    BAR_WIDTH=$(yq -r '.options.bar_width // 40' "$CONFIG")
    BAR_STYLE=$(yq -r '.options.bar_style // "ascii"' "$CONFIG")
    CTX_WARN_THRESHOLD=$(yq -r '.options.warn_threshold // 50' "$CONFIG")
    CTX_HIGH_THRESHOLD=$(yq -r '.options.high_threshold // 70' "$CONFIG")
    CTX_CRIT_THRESHOLD=$(yq -r '.options.crit_threshold // 80' "$CONFIG")
    CTX_OVERHEAD=$(yq -r '.options.ctx_overhead // 18000' "$CONFIG")
    CTX_BUFFER=$(yq -r '.options.ctx_buffer // 45000' "$CONFIG")
    FOCUS_WINDOW=$(yq -r '.options.focus_window // 15' "$CONFIG")
    FOCUS_FILE_THRESHOLD=$(yq -r '.options.focus_file_threshold // 70' "$CONFIG")
    FOCUS_DIR_THRESHOLD=$(yq -r '.options.focus_dir_threshold // 50' "$CONFIG")
    STRIDE_WINDOW=$(yq -r '.options.stride_window // 20' "$CONFIG")
    SPARKLINE_STYLE=$(yq -r '.options.sparkline_style // "braille"' "$CONFIG")

    # Parse domains
    ENABLED_DOMAINS=$(yq -r '.domains[]' "$CONFIG" 2>/dev/null | tr '\n' ' ')
}

# ============================================================================
# Generate config file from YAML options
# ============================================================================
generate_config() {
    cat > "$CONFIG_OUT" << EOF
# shellcheck shell=bash
# shellcheck disable=SC2034  # Variables used in other files
# ============================================================================
# Generated from config.yml - do not edit directly
# Run: task build (or ./build.sh) to regenerate
# ============================================================================

# Directories (configurable via env vars)
CLAUDE_DIR="\${CLAUDE_DIR:-\$HOME/.claude}"
CACHE_DIR="\${XDG_RUNTIME_DIR:-/tmp}"

# Progress bar
BAR_WIDTH=\${CLAUDE_METER_BAR_WIDTH:-${BAR_WIDTH}}
BAR_STYLE=\${CLAUDE_METER_BAR_STYLE:-${BAR_STYLE}}

# Context thresholds (percentage)
CTX_WARN_THRESHOLD=${CTX_WARN_THRESHOLD}
CTX_HIGH_THRESHOLD=${CTX_HIGH_THRESHOLD}
CTX_CRIT_THRESHOLD=${CTX_CRIT_THRESHOLD}

# Overhead estimates (tokens)
CTX_OVERHEAD=\${CLAUDE_METER_OVERHEAD:-${CTX_OVERHEAD}}
CTX_BUFFER=\${CLAUDE_METER_BUFFER:-${CTX_BUFFER}}

# Focus tracking
FOCUS_WINDOW=${FOCUS_WINDOW}
FOCUS_FILE_THRESHOLD=${FOCUS_FILE_THRESHOLD}
FOCUS_DIR_THRESHOLD=${FOCUS_DIR_THRESHOLD}

# Rhythm
STRIDE_WINDOW=${STRIDE_WINDOW}
SPARKLINE_STYLE="${SPARKLINE_STYLE}"
EOF
    echo "Generated: $CONFIG_OUT"
}

# ============================================================================
# Assemble components
# ============================================================================
assemble() {
    mkdir -p "$DIST_DIR"

    echo "Assembling with domains: $ENABLED_DOMAINS"

    # Start fresh
    > "$OUTPUT"

    # 1. Core files (sorted order)
    echo "  Adding core..."
    for f in "$SRC_DIR"/core/*.sh; do
        [ -f "$f" ] && cat "$f" >> "$OUTPUT" && echo "" >> "$OUTPUT"
    done

    # 2. Domain files (in config order)
    echo "  Adding domains..."
    for domain in $ENABLED_DOMAINS; do
        domain_file="$SRC_DIR/domains/${domain}.sh"
        if [ -f "$domain_file" ]; then
            cat "$domain_file" >> "$OUTPUT"
            echo "" >> "$OUTPUT"
        else
            echo "Warning: Domain not found: $domain_file" >&2
        fi
    done

    # 3. Output assembly
    echo "  Adding output..."
    for f in "$SRC_DIR"/output/*.sh; do
        [ -f "$f" ] && cat "$f" >> "$OUTPUT" && echo "" >> "$OUTPUT"
    done

    chmod +x "$OUTPUT"
    echo "Assembled: $OUTPUT"
}

# ============================================================================
# Minify
# ============================================================================
minify() {
    if ! command -v shfmt &>/dev/null; then
        echo "Error: shfmt is required. Install with: brew install shfmt" >&2
        exit 1
    fi

    shfmt -mn "$OUTPUT" > "$OUTPUT_MIN"
    chmod +x "$OUTPUT_MIN"

    # Report sizes
    orig=$(wc -c < "$OUTPUT")
    mini=$(wc -c < "$OUTPUT_MIN")
    pct=$((100 - (mini * 100 / orig)))
    echo ""
    echo "Assembled: $orig bytes"
    echo "Minified:  $mini bytes (${pct}% reduction)"
    echo "Output:    $OUTPUT_MIN"
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo "=== claude-meter build ==="
    echo ""

    parse_yaml
    generate_config
    assemble
    minify

    echo ""
    echo "Done! Run 'task link' to deploy."
}

main "$@"
