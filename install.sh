#!/bin/bash
# Claude Meter installer
# Usage: curl -fsSL https://raw.githubusercontent.com/gezibash/claude-meter/main/install.sh | bash

set -euo pipefail

REPO="gezibash/claude-meter"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
INSTALL_DIR="${CLAUDE_DIR:-$HOME/.claude}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}==>${NC} $1"; }
error() { echo -e "${RED}==>${NC} $1" >&2; }

# Check dependencies
check_deps() {
    local missing=()

    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    if ! command -v python3 &>/dev/null; then
        missing+=("python3")
    else
        # Check Python version >= 3.9
        py_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
        if [[ "$(echo -e "3.9\n$py_version" | sort -V | head -1)" != "3.9" ]]; then
            error "Python 3.9+ required (found $py_version)"
            exit 1
        fi
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        echo "Install with: brew install ${missing[*]}"
        exit 1
    fi
}

# Download a file
download() {
    local url="$1"
    local dest="$2"

    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget &>/dev/null; then
        wget -q "$url" -O "$dest"
    else
        error "Neither curl nor wget found"
        exit 1
    fi
}

main() {
    echo "Claude Meter Installer"
    echo "======================"
    echo ""

    # Check dependencies
    info "Checking dependencies..."
    check_deps

    # Create install directory
    info "Installing to $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    # Download files
    info "Downloading statusline.sh..."
    download "${BASE_URL}/dist/statusline.min.sh" "${INSTALL_DIR}/statusline.sh"
    chmod +x "${INSTALL_DIR}/statusline.sh"

    info "Downloading transcript_parser.py..."
    download "${BASE_URL}/transcript_parser.py" "${INSTALL_DIR}/transcript_parser.py"

    info "Downloading context_parser.py..."
    download "${BASE_URL}/context_parser.py" "${INSTALL_DIR}/context_parser.py"

    echo ""
    info "Installation complete!"
    echo ""
    echo "Files installed:"
    echo "  ${INSTALL_DIR}/statusline.sh"
    echo "  ${INSTALL_DIR}/transcript_parser.py"
    echo "  ${INSTALL_DIR}/context_parser.py"
    echo ""
    echo "Claude Code will automatically use the statusline on next session."
}

main "$@"
