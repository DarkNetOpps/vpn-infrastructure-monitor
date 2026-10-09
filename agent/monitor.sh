#!/usr/bin/env bash
set -u
BASE="/opt/net-monitor"
CONFIG="$BASE/config.conf"
if [[ ! -r "$CONFIG" ]]; then
  echo "ERROR: Missing config: $CONFIG" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG"
LOG_DIR="$BASE/logs"
JSON_DIR="$LOG_DIR/json"
mkdir -p "$JSON_DIR"
chmod 700 "$BASE" "$LOG_DIR" "$JSON_DIR" 2>/dev/null || true

TIME="$(date '+%Y-%m-%d %H:%M:%S%z')"
DATE="$(date '+%Y-%m-%d')"
JSON_FILE="$JSON_DIR/$DATE.jsonl"
READABLE="$LOG_DIR/readable.log"
IFACE="$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')"
IFACE="${IFACE:-unknown}"

statv() {
  local key="$1"
  if [[ "$IFACE" != unknown && -r "/sys/class/net/$IFACE/statistics/$key" ]]; then
    cat "/sys/class/net/$IFACE/statistics/$key"
  else
    echo 0
  fi
}
RX1="$(statv rx_bytes)"; TX1="$(statv tx_bytes)"
sleep 1
RX2="$(statv rx_bytes)"; TX2="$(statv tx_bytes)"
RX_MBPS=$(( (RX2-RX1)*8/1000000 )); TX_MBPS=$(( (TX2-TX1)*8/1000000 ))
RX_ERR="$(statv rx_errors)"; TX_ERR="$(statv tx_errors)"
RX_DROP="$(statv rx_dropped)"; TX_DROP="$(statv tx_dropped)"

# CPU usage from /proc/stat deltas (percentage, one-second sample).
read -r _ U1 N1 S1 I1 W1 Q1 SQ1 ST1 _ < /proc/stat
sleep 1
read -r _ U2 N2 S2 I2 W2 Q2 SQ2 ST2 _ < /proc/stat
DU=$((U2+N2-U1-N1)); DS=$((S2+Q2+SQ2-S1-Q1-SQ1)); DI=$((I2-I1)); DW=$((W2-W1)); DST=$((ST2-ST1))
DT=$((DU+DS+DI+DW+DST))
if (( DT > 0 )); then CPU_USER=$((DU*100/DT)); CPU_SYSTEM=$((DS*100/DT)); CPU_IDLE=$((DI*100/DT)); CPU_IOWAIT=$((DW*100/DT)); CPU_STEAL=$((DST*100/DT)); CPU_USED=$(((DU+DS+DST)*100/DT)); else CPU_USER=0; CPU_SYSTEM=0; CPU_IDLE=0; CPU_IOWAIT=0; CPU_STEAL=0; CPU_USED=0; fi

RAM_TOTAL="$(free -m | awk '/^Mem:/ {print $2}')"
RAM_USED="$(free -m | awk '/^Mem:/ {print $3}')"
RAM_FREE="$(free -m | awk '/^Mem:/ {print $7}')"
read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg
UPTIME="$(cut -d' ' -f1 /proc/uptime)"
DISK_USED="$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"

EST="$(ss -Hant state established 2>/dev/null | wc -l)"
TIMEWAIT="$(ss -Hant state time-wait 2>/dev/null | wc -l)"
SYNRECV="$(ss -Hant state syn-recv 2>/dev/null | wc -l)"
CLOSEWAIT="$(ss -Hant state close-wait 2>/dev/null | wc -l)"
OPEN_FILES="$(awk '{print $1}' /proc/sys/fs/file-nr)"
FILE_MAX="$(cat /proc/sys/fs/file-max)"
CT_CURRENT="N/A"; CT_MAX="N/A"
if [[ -r /proc/sys/net/netfilter/nf_conntrack_count ]]; then
  CT_CURRENT="$(cat /proc/sys/net/netfilter/nf_conntrack_count)"
  CT_MAX="$(cat /proc/sys/net/netfilter/nf_conntrack_max)"
fi

service_state() { systemctl is-active "$1" 2>/dev/null || true; }
service_pid() { systemctl show "$1" -p MainPID --value 2>/dev/null || echo 0; }
XUI="$(service_state x-ui)"; HPN="$(service_state hpn-reverse)"
HPNSSH="$(service_state hpnssh)"; JET="$(service_state jet-nginx)"
XUI_PID="$(service_pid x-ui)"; HPN_PID="$(service_pid hpn-reverse)"
HPNSSH_PID="$(service_pid hpnssh)"; JET_PID="$(service_pid jet-nginx)"

port_count() {
  local port="${1:-}"
  if [[ "$port" =~ ^[0-9]+$ ]]; then
    ss -Hant 2>/dev/null | awk -v p="$port" '($4 ~ ":"p"$") || ($5 ~ ":"p"$") {n++} END {print n+0}'
  else echo 0; fi
}
HPN_CONN="$(port_count "${HPN_PORT:-}")"; JET_CONN="$(port_count "${JET_PORT:-}")"
TUNNEL_PORTS="${TUNNEL_PORTS:-}"
HPN_ERR="$(journalctl -u hpn-reverse --since '2 min ago' --no-pager 2>/dev/null | grep -Eic 'error|fail|closed|timeout|disconnect|reset' || true)"
XUI_ERR="$(journalctl -u x-ui --since '2 min ago' --no-pager 2>/dev/null | grep -Eic 'error|fail|timeout|reset' || true)"
JET_ERR="$(journalctl -u jet-nginx --since '2 min ago' --no-pager 2>/dev/null | grep -Eic 'error|fail|timeout|reset' || true)"
KERNEL_ERR="$(journalctl -k --since '2 min ago' --no-pager 2>/dev/null | grep -Eic 'NETDEV WATCHDOG|out of memory|oom-kill|conntrack.*full|link is down|transmit.*timeout|I/O error' || true)"
KERNEL_TAIL="$(journalctl -k --since '2 min ago' --no-pager 2>/dev/null | grep -Ei 'NETDEV WATCHDOG|out of memory|oom-kill|conntrack.*full|link is down|transmit.*timeout|I/O error' | tail -5 || true)"

export TIME DATE SERVER_NAME REMOTE IFACE RX_MBPS TX_MBPS RX_ERR TX_ERR RX_DROP TX_DROP
export CPU_USER CPU_SYSTEM CPU_IDLE CPU_IOWAIT CPU_STEAL CPU_USED RAM_TOTAL RAM_USED RAM_FREE LOAD1 LOAD5 LOAD15 UPTIME DISK_USED
export EST TIMEWAIT SYNRECV CLOSEWAIT OPEN_FILES FILE_MAX CT_CURRENT CT_MAX
export XUI HPN HPNSSH JET XUI_PID HPN_PID HPNSSH_PID JET_PID HPN_CONN JET_CONN
export HPN_ERR XUI_ERR JET_ERR KERNEL_ERR KERNEL_TAIL HPN_PORT JET_PORT TUNNEL_PORTS

python3 - "$JSON_FILE" "$READABLE" <<'PY'
import json, os, re, subprocess, sys

def v(k, default="N/A"):
    return os.environ.get(k, default)
def n(k):
    try: return int(v(k, "0"))
    except (ValueError, TypeError): return 0

def custom_tunnels():
    raw = v("TUNNEL_PORTS", "")
    if not raw:
        return []

    try:
        output = subprocess.run(
            ["ss", "-Hant"],
            check=False, capture_output=True, text=True, timeout=5
        ).stdout.splitlines()
    except Exception:
        output = []

    result = []
    for item in raw.split(","):
        if ":" not in item:
            continue
        name, port = item.rsplit(":", 1)
        if not name or not port.isdigit() or not (1 <= int(port) <= 65535):
            continue

        count = 0
        for row in output:
            fields = row.split()
            if len(fields) < 5:
                continue
            local_addr, peer_addr = fields[-2], fields[-1]
            suffix = ":" + port
            if local_addr.endswith(suffix) or peer_addr.endswith(suffix):
                count += 1

        result.append({
            "name": name,
            "port": int(port),
            "connections": count
        })
    return result

data = {
  "time": v("TIME"), "server": v("SERVER_NAME", "unknown"), "remote": v("REMOTE", "unknown"),
  "cpu": {"user": str(n("CPU_USER")), "system": str(n("CPU_SYSTEM")), "idle": str(n("CPU_IDLE")), "iowait": str(n("CPU_IOWAIT")), "steal": str(n("CPU_STEAL")), "used_percent": n("CPU_USED")},
 "ram": {"used_mb": v("RAM_USED"), "total_mb": v("RAM_TOTAL"), "available_mb": v("RAM_FREE")},
  "load": {"1m": v("LOAD1"), "5m": v("LOAD5"), "15m": v("LOAD15")},
  "network": {"iface": v("IFACE"), "rx_mbps": v("RX_MBPS"), "tx_mbps": v("TX_MBPS"), "rx_drop": v("RX_DROP"), "tx_drop": v("TX_DROP"), "rx_errors": v("RX_ERR"), "tx_errors": v("TX_ERR")},
  "tcp": {"established": v("EST"), "time_wait": v("TIMEWAIT"), "syn_recv": v("SYNRECV"), "close_wait": v("CLOSEWAIT")},
  "socket": {"open": v("OPEN_FILES"), "max": v("FILE_MAX")},
  "conntrack": {"current": v("CT_CURRENT"), "max": v("CT_MAX")},
  "services": {"xui": v("XUI"), "hpn": v("HPN"), "hpnssh": v("HPNSSH"), "jet": v("JET")},
  "service_pids": {"xui": v("XUI_PID"), "hpn": v("HPN_PID"), "hpnssh": v("HPNSSH_PID"), "jet": v("JET_PID")},
  "tunnel": {"hpn": v("HPN_CONN"), "jet": v("JET_CONN"), "hpn_port": v("HPN_PORT"), "jet_port": v("JET_PORT")},
  "tunnels": custom_tunnels(),
  "errors": {"hpn": v("HPN_ERR"), "xui": v("XUI_ERR"), "jet": v("JET_ERR"), "kernel": v("KERNEL_ERR"), "kernel_details": v("KERNEL_TAIL", "")},
  "system": {"uptime_seconds": v("UPTIME"), "root_disk_used_percent": v("DISK_USED")}
}
line = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
with open(sys.argv[1], "a", encoding="utf-8") as f: f.write(line + "\n")
with open(sys.argv[2], "a", encoding="utf-8") as f: f.write(line + "\n")
PY

echo "Monitor snapshot saved: $JSON_FILE"
