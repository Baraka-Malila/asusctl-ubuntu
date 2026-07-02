#!/usr/bin/env bash
# Phase 1 Task 2 teardown: removes the 6.3.8 test install. Idempotent.
# Run: sudo bash scripts/phase1-teardown-638-test.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (sudo bash $0)" >&2
    exit 1
fi

echo "==> Stopping asusd-638-test.service"
systemctl stop    asusd-638-test.service 2>/dev/null || true
systemctl disable asusd-638-test.service 2>/dev/null || true

echo "==> Removing installed files"
rm -f /etc/systemd/system/asusd-638-test.service
rm -f /etc/dbus-1/system.d/asusd-638-test.conf
rm -f /usr/local/sbin/asusd-638
rm -f /usr/local/bin/asusctl-638

echo "==> Reloading systemd + dbus"
systemctl daemon-reload
systemctl reload dbus

echo "==> Done. FA507NV state unchanged. Existing v1.0.1 test install (if any) untouched."
