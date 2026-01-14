# shellcheck shell=bash
# shellcheck disable=SC2034  # Variables used in other files
# ============================================================================
# Constants: Non-configurable values (hardcoded)
# For configurable options, see config.yml -> generates 05-config.sh
# ============================================================================

# Stride acceleration thresholds
STRIDE_ACCEL_HIGH=0.15 # Delta threshold for strong acceleration (« »)
STRIDE_ACCEL_LOW=0.05  # Delta threshold for mild acceleration (‹ ›)
STRIDE_MIN_RESPONSES=2 # Min claude responses before showing acceleration

# Revision tracking
REV_THRESHOLD=5 # Edit count to trigger revision warning

# Timing
HUMAN_INACTIVITY_GAP=1800 # Gaps > this (seconds) = human away

# Display limits
MAX_SKILLS_SHOWN=3   # Max skills to display
MAX_MCP_SHOWN=5      # Max MCP servers to display
MAX_COMMANDS_SHOWN=3 # Max commands to display

# Sparklines
SPARKLINE_LENGTH=6 # Number of data points to display

# ============================================================================
# Domain configuration (toggle and ordering) - runtime via env vars
# ============================================================================
SHOW_RESOURCES=${CLAUDE_METER_RESOURCES:-1}
SHOW_RHYTHM=${CLAUDE_METER_RHYTHM:-1}
SHOW_FOCUS=${CLAUDE_METER_FOCUS:-1}
SHOW_INFRA=${CLAUDE_METER_INFRA:-1}
SHOW_SESSION=${CLAUDE_METER_SESSION:-1}

# Domain ordering (comma-separated) - runtime via env var
DOMAIN_ORDER=${CLAUDE_METER_ORDER:-"resources,rhythm,focus,infra,session"}
