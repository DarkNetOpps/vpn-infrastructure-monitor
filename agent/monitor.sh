#!/bin/bash

BASE="/opt/net-monitor"
CONFIG="$BASE/config.conf"

source "$CONFIG"

LOG_DIR="$BASE/logs"
JSON_DIR="$LOG_DIR/json"

mkdir -p "$JSON_DIR"

DATE=$(date +"%Y-%m-%d")
TIME=$(date +"%Y-%m-%d %H:%M:%S")

JSON_FILE="$JSON_DIR/$DATE.jsonl"
READABLE="$LOG_DIR/readable.log"


# =====================
# NETWORK INTERFACE
# =====================

IFACE=$(ip route | awk '/default/ {print $5; exit}')

RX1=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
TX1=$(cat /sys/class/net/$IFACE/statistics/tx_bytes)

sleep 1

RX2=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
TX2=$(cat /sys/class/net/$IFACE/statistics/tx_bytes)

RX_MBPS=$(( (RX2-RX1)*8/1000000 ))
TX_MBPS=$(( (TX2-TX1)*8/1000000 ))


RX_ERR=$(cat /sys/class/net/$IFACE/statistics/rx_errors 2>/dev/null || echo 0)
TX_ERR=$(cat /sys/class/net/$IFACE/statistics/tx_errors 2>/dev/null || echo 0)

RX_DROP=$(cat /sys/class/net/$IFACE/statistics/rx_dropped 2>/dev/null || echo 0)
TX_DROP=$(cat /sys/class/net/$IFACE/statistics/tx_dropped 2>/dev/null || echo 0)


# =====================
# CPU
# =====================

CPU=$(top -bn1 | grep "Cpu(s)")

CPU_USER=$(echo "$CPU" | awk '{print $2}')
CPU_SYS=$(echo "$CPU" | awk '{print $4}')
CPU_IDLE=$(echo "$CPU" | awk '{print $8}')
CPU_IOWAIT=$(echo "$CPU" | awk '{print $10}')

STEAL=$(vmstat 1 2 | tail -1 | awk '{print $17}')


# =====================
# RAM LOAD
# =====================

RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
RAM_FREE=$(free -m | awk '/Mem:/ {print $7}')

LOAD=$(cat /proc/loadavg)

LOAD1=$(echo $LOAD | awk '{print $1}')
LOAD5=$(echo $LOAD | awk '{print $2}')
LOAD15=$(echo $LOAD | awk '{print $3}')


UPTIME=$(uptime -p)


# =====================
# TCP
# =====================

EST=$(ss -ant state established | wc -l)
TIMEWAIT=$(ss -ant state time-wait | wc -l)
SYNRECV=$(ss -ant state syn-recv | wc -l)
CLOSEWAIT=$(ss -ant state close-wait | wc -l)


# =====================
# SOCKET
# =====================

OPEN_FILES=$(cat /proc/sys/fs/file-nr | awk '{print $1}')
FILE_MAX=$(cat /proc/sys/fs/file-max)


# =====================
# CONNTRACK
# =====================

if [ -f /proc/sys/net/netfilter/nf_conntrack_count ]; then

CT_CURRENT=$(cat /proc/sys/net/netfilter/nf_conntrack_count)
CT_MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max)

else

CT_CURRENT="N/A"
CT_MAX="N/A"

fi


# =====================
# SERVICES
# =====================

service_check(){

systemctl is-active --quiet $1

if [ $? -eq 0 ]; then
echo "UP"
else
echo "DOWN"
fi

}


XUI=$(service_check x-ui)
HPN=$(service_check hpn-reverse)
HPNSSH=$(service_check hpnssh)
JET=$(service_check jet-nginx)


# =====================
# PORTS
# =====================

HPN_CONN=$(ss -ant | grep ":$HPN_PORT " | wc -l)
JET_CONN=$(ss -ant | grep ":$JET_PORT " | wc -l)


# =====================
# ERRORS
# =====================

HPN_ERR=$(journalctl -u hpn-reverse --since "1 min ago" 2>/dev/null | grep -Ei "error|fail|closed" | wc -l)

XUI_ERR=$(journalctl -u x-ui --since "1 min ago" 2>/dev/null | grep -Ei "error|fail" | wc -l)

JET_ERR=$(journalctl -u jet-nginx --since "1 min ago" 2>/dev/null | grep -Ei "error|fail" | wc -l)



# =====================
# JSONL
# =====================

cat >> "$JSON_FILE" <<EOF
{"time":"$TIME","server":"$SERVER_NAME","remote":"$REMOTE","cpu":{"user":"$CPU_USER","system":"$CPU_SYS","iowait":"$CPU_IOWAIT","steal":"$STEAL"},"ram":{"used_mb":"$RAM_USED","total_mb":"$RAM_TOTAL"},"load":{"1m":"$LOAD1","5m":"$LOAD5","15m":"$LOAD15"},"network":{"iface":"$IFACE","rx_mbps":"$RX_MBPS","tx_mbps":"$TX_MBPS","rx_drop":"$RX_DROP","tx_drop":"$TX_DROP"},"tcp":{"established":"$EST","time_wait":"$TIMEWAIT","syn_recv":"$SYNRECV","close_wait":"$CLOSEWAIT"},"socket":{"open":"$OPEN_FILES","max":"$FILE_MAX"},"conntrack":{"current":"$CT_CURRENT","max":"$CT_MAX"},"services":{"xui":"$XUI","hpn":"$HPN","hpnssh":"$HPNSSH","jet":"$JET"},"tunnel":{"hpn":"$HPN_CONN","jet":"$JET_CONN"},"errors":{"hpn":"$HPN_ERR","xui":"$XUI_ERR","jet":"$JET_ERR"}}
EOF



# =====================
# READABLE LOG
# =====================

cat >> "$READABLE" <<EOF

==============================
$TIME
$SERVER_NAME -> $REMOTE

CPU:
USER $CPU_USER
SYSTEM $CPU_SYS
STEAL $STEAL

RAM:
$RAM_USED / $RAM_TOTAL MB

LOAD:
$LOAD1 $LOAD5 $LOAD15

NETWORK:
$IFACE
RX ${RX_MBPS} Mbps
TX ${TX_MBPS} Mbps

TCP:
ESTABLISHED $EST
TIME_WAIT $TIMEWAIT
SYN_RECV $SYNRECV
CLOSE_WAIT $CLOSEWAIT

SOCKET:
$OPEN_FILES / $FILE_MAX

CONNTRACK:
$CT_CURRENT / $CT_MAX

SERVICES:
x-ui $XUI
HPN $HPN
HPNSSH $HPNSSH
JET $JET

TUNNEL:
HPN $HPN_CONN
JET $JET_CONN

ERROR:
HPN $HPN_ERR
XUI $XUI_ERR
JET $JET_ERR

==============================

EOF
