#!/usr/bin/env bash
# Phase 0 helper: installs asusd + asusctl from upstream/asusctl/target/release into
# /usr/local plus a test-only systemd unit and dbus policy. Idempotent. Rollback via
# scripts/phase0-teardown.sh (created in Task 17).
#
# Run: sudo bash scripts/phase0-install-asusd-test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="$REPO_ROOT/upstream/asusctl"
BIN_ASUSD="$UPSTREAM/target/release/asusd"
BIN_ASUSCTL="$UPSTREAM/target/release/asusctl"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (sudo bash $0)" >&2
    exit 1
fi

for f in "$BIN_ASUSD" "$BIN_ASUSCTL" "$UPSTREAM/data/asusd.service" "$UPSTREAM/data/asusd.conf"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing $f — run Tasks 2 & 3 first" >&2
        exit 1
    fi
done

echo "==> Installing binaries to /usr/local"
install -m 755 "$BIN_ASUSD" /usr/local/sbin/asusd
install -m 755 "$BIN_ASUSCTL" /usr/local/bin/asusctl

echo "==> Installing test systemd unit → /etc/systemd/system/asusd-test.service"
sed 's|ExecStart=/usr/bin/asusd|ExecStart=/usr/local/sbin/asusd|' \
    "$UPSTREAM/data/asusd.service" > /etc/systemd/system/asusd-test.service
chmod 644 /etc/systemd/system/asusd-test.service

echo "==> Installing dbus policy → /etc/dbus-1/system.d/asusd-test.conf"
install -m 644 "$UPSTREAM/data/asusd.conf" /etc/dbus-1/system.d/asusd-test.conf

echo "==> Reloading systemd and dbus"
systemctl daemon-reload
systemctl reload dbus

echo "==> Starting asusd-test.service"
systemctl start asusd-test.service
sleep 2

echo "==> Service status:"
systemctl is-active asusd-test.service && echo "  active ✓" || { echo "  FAILED — see 'journalctl -u asusd-test' for details"; exit 1; }

echo "==> Installed files:"
ls -la /usr/local/sbin/asusd /usr/local/bin/asusctl /etc/systemd/system/asusd-test.service /etc/dbus-1/system.d/asusd-test.conf

echo "==> Done. Verify dbus registration with:"
echo "    gdbus introspect --system --dest org.asuslinux.Daemon --object-path /org/asuslinux"
