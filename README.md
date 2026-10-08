# VPN Infrastructure Monitor

Telegram based monitoring system for VPN infrastructure.

## Features

- Multi server monitoring
- Telegram reports
- JSON history logs
- CPU / RAM / TCP / Socket monitoring
- Tunnel status monitoring
- 30 days history retention

## Architecture

IR Servers:
Agent -> Collector

Master:
Collector + Telegram Bot
