#!/usr/bin/env bash
set -euo pipefail

BASE="/opt/net-monitor"
CONFIG_FILE="$BASE/config.conf"
JSON_DIR="$BASE/logs/json"
JSON_FILE="$JSON_DIR/$(date +%Y-%m-%d).jsonl"

if [[ ! -r "$CONFIG_FILE" ]]; then
    echo "ERROR: Cannot read $CONFIG_FILE" >&2
    exit 1
fi

# Load local, permission-restricted configuration.
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${COLLECTOR_URL:?COLLECTOR_URL is missing in config.conf}"
: "${API_KEY:?API_KEY is missing in config.conf}"

if [[ "$COLLECTOR_URL" != https://* &&
      "$COLLECTOR_URL" != http://* ]]; then
    echo "ERROR: Invalid COLLECTOR_URL" >&2
    exit 1
fi

if [[ "$COLLECTOR_URL" == *YOUR_MASTER_IP* ||
      "$API_KEY" == "CHANGE_THIS_SECRET" ]]; then
    echo "ERROR: Replace placeholder settings in config.conf" >&2
    exit 1
fi

if [[ ! -s "$JSON_FILE" ]]; then
    echo "ERROR: No JSON report found: $JSON_FILE" >&2
    exit 1
fi

DATA="$(tail -n 1 "$JSON_FILE")"

if [[ -z "$DATA" ]]; then
    echo "ERROR: Latest report is empty" >&2
    exit 1
fi

curl --fail --silent --show-error \
    --connect-timeout 5 \
    --max-time 20 \
    --request POST "$COLLECTOR_URL" \
    --header "Content-Type: application/json" \
    --header "X-API-Key: $API_KEY" \
    --data-binary "$DATA" \
    > /dev/null

echo "Report submitted successfully."
