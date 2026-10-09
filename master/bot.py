#!/usr/bin/env python3

import os
import json
import time
import requests
from datetime import datetime

BASE_DIR = "/opt/vpn-monitor/reports"
CONFIG_FILE = "/opt/vpn-monitor/bot_config.json"

STALE_SECONDS = 120


def load_config():
    with open(CONFIG_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def parse_time(value):
    if not value:
        return None

    formats = [
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
    ]

    for fmt in formats:
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            pass

    return None


def get_age_seconds(report):
    timestamp = report.get("received_at") or report.get("time")

    dt = parse_time(timestamp)

    if not dt:
        return None

    return max(0, int((datetime.now() - dt).total_seconds()))


def status_icon(report):
    age = get_age_seconds(report)

    if age is None:
        return "🟡"

    if age > STALE_SECONDS:
        return "🔴"

    return "🟢"


def fmt(value, default="-"):
    if value is None or value == "":
        return default

    return str(value)


def service_icon(value):
    return "🟢" if str(value).upper() in ("UP", "ACTIVE", "RUNNING") else "🔴"


def load_reports():
    reports = []

    if not os.path.isdir(BASE_DIR):
        return reports

    for server_id in sorted(os.listdir(BASE_DIR)):
        server_dir = os.path.join(BASE_DIR, server_id)

        if not os.path.isdir(server_dir):
            continue

        latest_file = os.path.join(server_dir, "latest.json")

        if not os.path.isfile(latest_file):
            continue

        try:
            with open(latest_file, "r", encoding="utf-8") as f:
                data = json.load(f)

            reports.append(data)

        except Exception as e:
            print(f"Failed to read {latest_file}: {e}")

    return reports


def format_report(report):
    server = fmt(report.get("server"), "UNKNOWN")
    remote = fmt(report.get("remote"), "UNKNOWN")

    state = status_icon(report)
    age = get_age_seconds(report)

    if age is None:
        freshness = "NO TIME"
    elif age > STALE_SECONDS:
        freshness = f"STALE {age}s"
    else:
        freshness = f"{age}s"

    cpu = report.get("cpu", {})
    ram = report.get("ram", {})
    load = report.get("load", {})
    network = report.get("network", {})
    tcp = report.get("tcp", {})
    socket = report.get("socket", {})
    conntrack = report.get("conntrack", {})
    services = report.get("services", {})
    tunnel = report.get("tunnel", {})
    custom_tunnels = report.get("tunnels")
    errors = report.get("errors", {})

    lines = [
        f"{server} → {remote} {state} {freshness}",

        f"CPU U/S/I/ST "
        f"{fmt(cpu.get('user'))}/"
        f"{fmt(cpu.get('system'))}/"
        f"{fmt(cpu.get('iowait'))}/"
        f"{fmt(cpu.get('steal'))}%",

        f"RAM {fmt(ram.get('used_mb'))}/{fmt(ram.get('total_mb'))} MB",

        f"LOAD "
        f"{fmt(load.get('1m'))}/"
        f"{fmt(load.get('5m'))}/"
        f"{fmt(load.get('15m'))}",

        f"NET "
        f"RX {fmt(network.get('rx_mbps'))} Mbps | "
        f"TX {fmt(network.get('tx_mbps'))} Mbps | "
        f"DROP "
        f"{fmt(network.get('rx_drop'))}/"
        f"{fmt(network.get('tx_drop'))}",

        f"TCP "
        f"E {fmt(tcp.get('established'))} | "
        f"W {fmt(tcp.get('time_wait'))} | "
        f"S {fmt(tcp.get('syn_recv'))} | "
        f"C {fmt(tcp.get('close_wait'))}",

        f"SOCK {fmt(socket.get('open'))}/{fmt(socket.get('max'))}",

        f"CT {fmt(conntrack.get('current'))}/{fmt(conntrack.get('max'))}",

        *(
            [
                "TUNNELS",
                *[
                    f"{item.get('name', 'Tunnel')} : "
                    f"{fmt(item.get('connections'))} connections "
                    f"(port {fmt(item.get('port'))})"
                    for item in custom_tunnels
                    if isinstance(item, dict)
                ],
            ]
            if isinstance(custom_tunnels, list) and custom_tunnels
            else (
                ["TUNNELS none configured"]
                if isinstance(custom_tunnels, list)
                else [
                    f"TUN HPN {fmt(tunnel.get('hpn'))} | "
                    f"JET {fmt(tunnel.get('jet'))}"
                ]
            )
        ),

        "SVC "
        f"XUI {service_icon(services.get('xui'))} "
        f"HPN {service_icon(services.get('hpn'))} "
        f"SSH {service_icon(services.get('hpnssh'))} "
        f"JET {service_icon(services.get('jet'))}",

        f"ERR "
        f"HPN {fmt(errors.get('hpn'))} | "
        f"XUI {fmt(errors.get('xui'))} | "
        f"JET {fmt(errors.get('jet'))}",
    ]

    return "\n".join(lines)


def build_message(reports):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    lines = [
        "📡 VPN INFRASTRUCTURE MONITOR",
        f"⏱ {now}",
        f"🖥 SERVERS: {len(reports)}",
        "",
    ]

    if not reports:
        lines.append("⚠️ No reports received yet.")
        return "\n".join(lines)

    for index, report in enumerate(reports):
        lines.append(format_report(report))

        if index != len(reports) - 1:
            lines.append("")
            lines.append("━━━━━━━━━━━━")

    return "\n".join(lines)


def send_telegram(bot_token, chat_id, text):
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"

    payload = {
        "chat_id": chat_id,
        "text": text,
        "disable_web_page_preview": True,
    }

    response = requests.post(
        url,
        json=payload,
        timeout=20,
    )

    if response.status_code != 200:
        raise RuntimeError(
            f"Telegram API error {response.status_code}: {response.text}"
        )

    return response.json()


def main():
    config = load_config()

    bot_token = config["bot_token"]
    chat_id = config["chat_id"]
    interval = int(config.get("interval", 60))

    print("VPN Monitor Telegram Bot started")

    while True:
        try:
            reports = load_reports()

            message = build_message(reports)

            # Telegram limit is 4096 characters.
            if len(message) > 4000:
                message = message[:3990] + "\n..."

            result = send_telegram(
                bot_token,
                chat_id,
                message,
            )

            if result.get("ok"):
                print(
                    f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] "
                    f"Sent {len(reports)} server reports"
                )
            else:
                print(f"Telegram returned error: {result}")

        except Exception as e:
            print(
                f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] "
                f"ERROR: {e}"
            )

        time.sleep(interval)


if __name__ == "__main__":
    main()
