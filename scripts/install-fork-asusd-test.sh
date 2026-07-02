#!/usr/bin/env bash
# Phase 1 test install for our fork's asusd. Installs fork/asusctl/target/release
# binaries + a namespaced systemd unit (asusd-test.service) and dbus policy.
# Idempotent. Rollback via scripts/phase1-teardown.sh.
#
# On FA507NV: our asusd owns charge_control_end_threshold. The existing
# battery-charge-threshold.service also writes there — we stop it here so the
# two don't fight, and remember its prior state so teardown can restore it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FORK="$REPO_ROOT/fork/asusctl"
STATE_DIR="/var/lib/asus-phase1-fork"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (sudo bash $0)" >&2
    exit 1
fi

for f in "$FORK/target/release/asusd" "$FORK/target/release/asusctl" \
         "$FORK/data/asusd.service" "$FORK/data/asusd.conf"; do
    [ -f "$f" ] || { echo "ERROR: missing $f — run scripts/build-fork-asusctl.sh first" >&2; exit 1; }
done

mkdir -p "$STATE_DIR"

echo "==> Recording prior state of battery-charge-threshold.service"
systemctl is-enabled battery-charge-threshold.service > "$STATE_DIR/batsvc.enabled" 2>&1 || echo "unknown" > "$STATE_DIR/batsvc.enabled"
systemctl is-active  battery-charge-threshold.service > "$STATE_DIR/batsvc.active"  2>&1 || echo "unknown" > "$STATE_DIR/batsvc.active"

echo "==> Stopping battery-charge-threshold.service (asusd will own the sysfs)"
systemctl stop battery-charge-threshold.service 2>/dev/null || true

echo "==> Installing binaries"
install -m 755 "$FORK/target/release/asusd"   /usr/local/sbin/asusd
install -m 755 "$FORK/target/release/asusctl" /usr/local/bin/asusctl

echo "==> Installing test systemd unit → /etc/systemd/system/asusd-test.service"
sed 's|ExecStart=/usr/bin/asusd|ExecStart=/usr/local/sbin/asusd|' \
    "$FORK/data/asusd.service" > /etc/systemd/system/asusd-test.service
chmod 644 /etc/systemd/system/asusd-test.service

echo "==> Installing dbus policy → /etc/dbus-1/system.d/asusd-test.conf"
install -m 644 "$FORK/data/asusd.conf" /etc/dbus-1/system.d/asusd-test.conf

echo "==> Reloading systemd + dbus"
systemctl daemon-reload
systemctl reload dbus

echo "==> Starting asusd-test.service"
systemctl start asusd-test.service
sleep 2

if systemctl is-active --quiet asusd-test.service; then
    echo "  active ✓"
else
    echo "  FAILED — journalctl -u asusd-test.service --no-pager -n 40:" >&2
    journalctl -u asusd-test.service --no-pager -n 40 >&2
    exit 1
fi

echo "==> Done. Prior battery-charge-threshold.service state saved to $STATE_DIR."
