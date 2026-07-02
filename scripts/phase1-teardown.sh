#!/usr/bin/env bash
# Phase 1 teardown: undoes install-fork-asusd-test.sh and install-fork-supergfxd-test.sh.
# Restores battery-charge-threshold.service to its prior active/enabled state.
# Idempotent.
set -euo pipefail

STATE_DIR="/var/lib/asus-phase1-fork"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (sudo bash $0)" >&2
    exit 1
fi

echo "==> Stopping test daemons"
systemctl stop    asusd-test.service      2>/dev/null || true
systemctl disable asusd-test.service      2>/dev/null || true
systemctl stop    supergfxd-test.service  2>/dev/null || true
systemctl disable supergfxd-test.service  2>/dev/null || true

echo "==> Removing installed files"
rm -f /etc/systemd/system/asusd-test.service
rm -f /etc/systemd/system/supergfxd-test.service
rm -f /etc/dbus-1/system.d/asusd-test.conf
rm -f /etc/dbus-1/system.d/supergfxd-test.conf
rm -f /usr/local/sbin/asusd
rm -f /usr/local/sbin/supergfxd
rm -f /usr/local/bin/asusctl
rm -f /usr/local/bin/supergfxctl

echo "==> Reloading systemd + dbus"
systemctl daemon-reload
systemctl reload dbus

if [ -f "$STATE_DIR/batsvc.active" ] && grep -q "^active$" "$STATE_DIR/batsvc.active"; then
    echo "==> Restoring battery-charge-threshold.service to active"
    systemctl start battery-charge-threshold.service 2>/dev/null || echo "  (start failed — check manually)"
fi

echo "==> Done. FA507NV state should now match pre-Phase-1-install."
