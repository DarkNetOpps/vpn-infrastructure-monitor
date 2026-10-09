#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/DarkNetOpps/vpn-infrastructure-monitor.git"
BRANCH="main"
ROLE="${1:-}"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root: bash install.sh master|agent"
    exit 1
fi

case "$ROLE" in
    master|agent) ;;
    *)
        echo "Usage: bash install.sh master|agent"
        exit 1
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

# اگر نصب‌کننده مستقیماً از GitHub اجرا شده، ابتدا مخزن را دریافت کن.
if [[ ! -f "$SCRIPT_DIR/install-master.sh" ||
      ! -f "$SCRIPT_DIR/install-agent.sh" ]]; then
    if ! command -v git >/dev/null 2>&1; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y git
    fi

    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMP_DIR/repo"
    SCRIPT_DIR="$TMP_DIR/repo"
fi

case "$ROLE" in
    master)
        echo "Starting MASTER installation..."
        exec bash "$SCRIPT_DIR/install-master.sh"
        ;;
    agent)
        echo "Starting AGENT installation..."
        exec bash "$SCRIPT_DIR/install-agent.sh"
        ;;
esac
