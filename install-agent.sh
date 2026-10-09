#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

APP_DIR="/opt/net-monitor"
CONFIG_FILE="$APP_DIR/config.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root." >&2
    exit 1
fi

for f in \
    "$SCRIPT_DIR/agent/monitor.sh" \
    "$SCRIPT_DIR/agent/sender.sh" \
    "$SCRIPT_DIR/systemd/net-monitor.service" \
    "$SCRIPT_DIR/systemd/net-monitor.timer"; do
    [[ -f "$f" ]] || {
        echo "ERROR: Missing file: $f" >&2
        exit 1
    }
done

bash -n "$SCRIPT_DIR/agent/monitor.sh"
bash -n "$SCRIPT_DIR/agent/sender.sh"

echo "=== VPN Monitor Agent Installer ==="
echo "Config and history will be preserved."

mkdir -p "$APP_DIR"

# Never overwrite local config or historical logs.
mkdir -p "$APP_DIR/logs/json"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo
    echo "First-time setup: enter this server's settings."
    read -r -p "Server name (e.g. IR-6): " SERVER_NAME
    read -r -p "Remote server name (e.g. TR-3): " REMOTE
    HPN_PORT=""
    JET_PORT=""
    TUNNEL_PORTS=""

    read -r -p "Number of custom tunnel ports (0-10): " TUNNEL_COUNT
    [[ "$TUNNEL_COUNT" =~ ^[0-9]+$ ]] || {
        echo "ERROR: Tunnel count must be a number from 0 to 10." >&2
        exit 1
    }
    (( 10#$TUNNEL_COUNT <= 10 )) || {
        echo "ERROR: Maximum is 10 tunnel ports." >&2
        exit 1
    }
    TUNNEL_COUNT=$((10#$TUNNEL_COUNT))

    for ((i=1; i<=TUNNEL_COUNT; i++)); do
        read -r -p "Tunnel $i name (e.g. MyTunnel): " TUN_NAME
        read -r -p "Tunnel $i port (e.g. 10990): " TUN_PORT

        [[ -n "$TUN_NAME" && "$TUN_NAME" != *","* &&
           "$TUN_NAME" != *":"* ]] || {
            echo "ERROR: Tunnel name must be nonempty and cannot contain comma or colon." >&2
            exit 1
        }

        [[ "$TUN_PORT" =~ ^[0-9]+$ ]] || {
            echo "ERROR: Tunnel port must be numeric." >&2
            exit 1
        }
        (( 10#$TUN_PORT >= 1 && 10#$TUN_PORT <= 65535 )) || {
            echo "ERROR: Tunnel port must be between 1 and 65535." >&2
            exit 1
        }

        [[ -z "$TUNNEL_PORTS" ]] || TUNNEL_PORTS+=","
        TUNNEL_PORTS+="$TUN_NAME:$TUN_PORT"
    done

    read -r -p "Collector URL (e.g. http://MASTER_IP:8080/report): " COLLECTOR_URL
    read -r -s -p "Collector API key: " API_KEY
    echo

    [[ -n "$SERVER_NAME" && -n "$REMOTE" ]] || {
        echo "ERROR: Server and remote names are required." >&2
        exit 1
    }

    [[ "$COLLECTOR_URL" =~ ^https?://[^[:space:]]+/report$ ]] || {
        echo "ERROR: Collector URL must be an HTTP(S) URL ending in /report." >&2
        exit 1
    }

    [[ -n "$API_KEY" && "$API_KEY" != "CHANGE_THIS_SECRET" &&
       "$API_KEY" != *[[:space:]]* ]] || {
        echo "ERROR: API key is empty, a placeholder, or contains whitespace." >&2
        exit 1
    }

    # Write shell-safe values without evaluating user input.
    {
        printf 'SERVER_NAME=%q\n' "$SERVER_NAME"
        printf 'REMOTE=%q\n' "$REMOTE"
        printf 'HPN_PORT=%q\n' "$HPN_PORT"
        printf 'JET_PORT=%q\n' "$JET_PORT"
        printf 'TUNNEL_PORTS=%q\n' "$TUNNEL_PORTS"
        printf 'COLLECTOR_URL=%q\n' "$COLLECTOR_URL"
        printf 'API_KEY=%q\n' "$API_KEY"
    } > "$CONFIG_FILE"

    chmod 600 "$CONFIG_FILE"
    echo "Created $CONFIG_FILE"
else
    echo "Preserving existing config: $CONFIG_FILE"
fi

# Check the local config before installing/updating services.
[[ -r "$CONFIG_FILE" ]] || {
    echo "ERROR: Config is not readable." >&2
    exit 1
}

# shellcheck disable=SC1090
source "$CONFIG_FILE"

HPN_PORT="${HPN_PORT:-}"
JET_PORT="${JET_PORT:-}"
TUNNEL_PORTS="${TUNNEL_PORTS:-}"

: "${SERVER_NAME:?Missing SERVER_NAME in config}"
: "${REMOTE:?Missing REMOTE in config}"
: "${COLLECTOR_URL:?Missing COLLECTOR_URL in config}"
: "${API_KEY:?Missing API_KEY in config}"

[[ -n "$API_KEY" && "$API_KEY" != "CHANGE_THIS_SECRET" &&
   "$API_KEY" != *[[:space:]]* ]] || {
    echo "ERROR: API key is empty, a placeholder, or contains whitespace." >&2
    exit 1
}

[[ "$COLLECTOR_URL" =~ ^https?://[^[:space:]]+/report$ ]] || {
    echo "ERROR: Invalid COLLECTOR_URL in config." >&2
    exit 1
}

[[ "$COLLECTOR_URL" != *YOUR_MASTER_IP* &&
   "$API_KEY" != "CHANGE_THIS_SECRET" ]] || {
    echo "ERROR: Replace placeholder values in config.conf." >&2
    exit 1
}

echo "Installing agent scripts..."
install -m 0755 "$SCRIPT_DIR/agent/monitor.sh" "$APP_DIR/monitor.sh"
install -m 0755 "$SCRIPT_DIR/agent/sender.sh" "$APP_DIR/sender.sh"
chmod 600 "$CONFIG_FILE"

echo "Installing systemd units..."
install -m 0644 "$SCRIPT_DIR/systemd/net-monitor.service" \
    /etc/systemd/system/net-monitor.service
install -m 0644 "$SCRIPT_DIR/systemd/net-monitor.timer" \
    /etc/systemd/system/net-monitor.timer

systemctl daemon-reload
systemctl enable --now net-monitor.timer

echo
echo "Agent files installed."
echo "The timer is enabled; the first scheduled run is not forced here."
echo "No VPN tunnel services were restarted."
echo
systemctl --no-pager status net-monitor.timer || true
