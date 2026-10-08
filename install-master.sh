#!/usr/bin/env bash

set -euo pipefail

APP_DIR="/opt/vpn-monitor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_FILE="$APP_DIR/config.json"
BOT_CONFIG="$APP_DIR/bot_config.json"

VENV_DIR="$APP_DIR/venv"

echo
echo "======================================"
echo " VPN Infrastructure Monitor - MASTER"
echo "======================================"
echo

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this installer as root."
    exit 1
fi

echo "[1/8] Installing system dependencies..."

apt-get update

apt-get install -y \
    python3 \
    python3-venv \
    python3-pip \
    curl

echo "[2/8] Preparing application directory..."

mkdir -p "$APP_DIR"
mkdir -p "$APP_DIR/reports"

echo "[3/8] Creating Python virtual environment..."

if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python" -m pip install --upgrade pip

echo "[4/8] Installing Python dependencies..."

"$VENV_DIR/bin/pip" install \
    -r "$SCRIPT_DIR/requirements.txt"

echo "[5/8] Installing application files..."

install -m 0755 \
    "$SCRIPT_DIR/master/collector.py" \
    "$APP_DIR/collector.py"

install -m 0755 \
    "$SCRIPT_DIR/master/bot.py" \
    "$APP_DIR/bot.py"

echo "[6/8] Installing configuration..."

if [[ ! -f "$CONFIG_FILE" ]]; then

    echo
    echo "Collector API key is required."
    echo "Use a strong random value."
    echo

    read -r -s -p "Enter Collector API key: " API_KEY
    echo

    if [[ -z "$API_KEY" ]]; then
        echo "ERROR: API key cannot be empty."
        exit 1
    fi

    cat > "$CONFIG_FILE" <<EOF
{
  "api_key": "$API_KEY"
}
EOF

    chmod 600 "$CONFIG_FILE"

    echo "Created $CONFIG_FILE"

else

    echo "Existing collector config preserved:"
    echo "$CONFIG_FILE"

fi


if [[ ! -f "$BOT_CONFIG" ]]; then

    echo
    echo "Telegram Bot configuration required."
    echo

    read -r -p "Telegram Bot Token: " BOT_TOKEN
    read -r -p "Telegram Chat ID: " CHAT_ID

    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        echo "ERROR: Bot token and chat ID cannot be empty."
        exit 1
    fi

    cat > "$BOT_CONFIG" <<EOF
{
  "bot_token": "$BOT_TOKEN",
  "chat_id": "$CHAT_ID",
  "interval": 60
}
EOF

    chmod 600 "$BOT_CONFIG"

    echo "Created $BOT_CONFIG"

else

    echo "Existing Telegram config preserved:"
    echo "$BOT_CONFIG"

fi

echo "[7/8] Installing systemd services..."

install -m 0644 \
    "$SCRIPT_DIR/systemd/vpn-monitor-collector.service" \
    /etc/systemd/system/vpn-monitor-collector.service

install -m 0644 \
    "$SCRIPT_DIR/systemd/vpn-monitor-bot.service" \
    /etc/systemd/system/vpn-monitor-bot.service

systemctl daemon-reload

echo "[8/8] Enabling services..."

systemctl enable vpn-monitor-collector.service
systemctl enable vpn-monitor-bot.service

systemctl restart vpn-monitor-collector.service
systemctl restart vpn-monitor-bot.service

echo
echo "======================================"
echo " Installation completed successfully"
echo "======================================"
echo

echo "Collector:"
systemctl --no-pager --full status vpn-monitor-collector.service || true

echo
echo "Telegram Bot:"
systemctl --no-pager --full status vpn-monitor-bot.service || true

echo
echo "Reports:"
echo "$APP_DIR/reports"

echo
echo "Config:"
echo "$CONFIG_FILE"
echo "$BOT_CONFIG"

echo
echo "Done."
