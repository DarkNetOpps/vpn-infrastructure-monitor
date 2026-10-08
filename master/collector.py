from flask import Flask, request, jsonify
import os
import json
from datetime import datetime, timedelta

app = Flask(__name__)

BASE_DIR = "/opt/vpn-monitor/reports"
CONFIG_FILE = "/opt/vpn-monitor/config.json"

RETENTION_DAYS = 30


def load_config():
    if not os.path.isfile(CONFIG_FILE):
        raise RuntimeError(
            f"Config file not found: {CONFIG_FILE}"
        )

    with open(CONFIG_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def get_api_key():
    config = load_config()
    api_key = config.get("api_key")

    if not api_key:
        raise RuntimeError(
            "api_key is missing from config.json"
        )

    return api_key


def cleanup_history():
    if not os.path.isdir(BASE_DIR):
        return

    limit = datetime.now() - timedelta(days=RETENTION_DAYS)

    for root, dirs, files in os.walk(BASE_DIR):
        for file in files:
            if not file.endswith(".json"):
                continue

            path = os.path.join(root, file)

            try:
                mtime = datetime.fromtimestamp(
                    os.path.getmtime(path)
                )

                if mtime < limit:
                    os.remove(path)

            except Exception:
                pass


def save_report(data):
    server_id = data.get("id")

    if not server_id:
        server_id = data.get("server", "UNKNOWN")

        server_id = (
            server_id
            .replace("🇮🇷", "")
            .replace(" ", "")
        )

    server_id = str(server_id)

    server_dir = os.path.join(
        BASE_DIR,
        server_id
    )

    history_dir = os.path.join(
        server_dir,
        "history"
    )

    os.makedirs(
        history_dir,
        exist_ok=True
    )

    now = datetime.now()

    data["received_at"] = now.strftime(
        "%Y-%m-%d %H:%M:%S"
    )

    with open(
        os.path.join(
            server_dir,
            "latest.json"
        ),
        "w",
        encoding="utf-8"
    ) as f:
        json.dump(
            data,
            f,
            indent=2,
            ensure_ascii=False
        )

    filename = now.strftime(
        "%Y-%m-%d_%H-%M.json"
    )

    with open(
        os.path.join(
            history_dir,
            filename
        ),
        "w",
        encoding="utf-8"
    ) as f:
        json.dump(
            data,
            f,
            indent=2,
            ensure_ascii=False
        )

    cleanup_history()


@app.route("/report", methods=["POST"])
def report():
    try:
        key = request.headers.get("X-API-Key")

        if not key or key != get_api_key():
            return jsonify({
                "status": "error",
                "message": "unauthorized"
            }), 401

        data = request.get_json(silent=True)

        if not isinstance(data, dict):
            return jsonify({
                "status": "error",
                "message": "invalid json"
            }), 400

        save_report(data)

        return jsonify({
            "status": "ok",
            "server": data.get("server")
        })

    except Exception as e:
        print(f"REPORT ERROR: {e}")

        return jsonify({
            "status": "error",
            "message": "internal server error"
        }), 500


@app.route("/status")
def status():
    servers = []

    if os.path.exists(BASE_DIR):
        for item in os.listdir(BASE_DIR):
            path = os.path.join(BASE_DIR, item)

            if os.path.isdir(path):
                servers.append(item)

    return jsonify({
        "collector": "online",
        "reports": sorted(servers)
    })


if __name__ == "__main__":
    os.makedirs(
        BASE_DIR,
        exist_ok=True
    )

    app.run(
        host="0.0.0.0",
        port=8080
    )
