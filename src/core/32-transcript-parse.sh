# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # Variables from core/input, used in other files
# ============================================================================
# Transcript Parse: Single Python call extracts all metrics
# Provides: T_* variables (timing, stride, mode, focus, infra)
# Requires: transcript, SLEEP_TIMES (from core/input, core/helpers)
# ============================================================================

if [ -f "$transcript" ]; then
    # Build config JSON from shell variables
    config_json=$(
        cat <<EOF
{"stride_window":${STRIDE_WINDOW:-20},"focus_window":${FOCUS_WINDOW:-15},"focus_file_threshold":${FOCUS_FILE_THRESHOLD:-70},"focus_dir_threshold":${FOCUS_DIR_THRESHOLD:-50},"inactivity_gap":${HUMAN_INACTIVITY_GAP:-1800},"sparkline_length":${SPARKLINE_LENGTH:-6},"sleep_times":${SLEEP_TIMES:-[]}}
EOF
    )

    # Single Python call - eval the output
    eval "$(python3 "${CLAUDE_DIR}/transcript_parser.py" "$transcript" "$config_json" 2>/dev/null)"
fi
