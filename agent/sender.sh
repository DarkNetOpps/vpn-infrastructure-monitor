#!/bin/bash

# ==============================
# VPN Monitor Sender
# ==============================

COLLECTOR="http://YOUR_MASTER_IP:8080/report"

JSON_FILE="/opt/net-monitor/logs/json/$(date +"%Y-%m-%d").jsonl"


if [ ! -f "$JSON_FILE" ]; then
    exit 1
fi


DATA=$(tail -1 "$JSON_FILE")


curl -s \
-X POST "$COLLECTOR" \
-H "Content-Type: application/json" \
-H "X-API-Key: CHANGE_THIS_SECRET" \
-d "$DATA"
> /dev/null
