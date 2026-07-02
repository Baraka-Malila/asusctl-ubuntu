#!/usr/bin/env bash
# Phase 1 Task 2 helper: installs 6.3.8's asusd + asusctl side-by-side with the
# v1.0.1 test daemon (Phase 0). Uses a namespaced systemd unit and dbus policy
# so we can flip between the two without collision. 6.3.8 uses a different bus
# name (xyz.ljones.Asusd) than v1.0.1 (org.asuslinux.Daemon) so they can even
# coexist — but we still stop v1.0.1 first to isolate observations.
#
# Run: sudo bash scripts/phase1-install-asusd-638-test.sh
# Teardown: sudo bash scripts/phase1-teardown-638-test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/upstream/asusctl-638"
BIN_ASUSD="$SRC/target/release/asusd"
BIN_ASUSCTL="$SRC/target/release/asusctl"
SVC_SRC="$SRC/data/asusd.service"
DBUS_SRC="$SRC/data/asusd.conf"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (sudo bash $0)" >&2
    exit 1
fi

for f in "$BIN_ASUSD" "$BIN_ASUSCTL" "$SVC_SRC" "$DBUS_SRC"; do
    [ -f "$f" ] || { echo "ERROR: missing $f — run scripts/fetch-upstream-asusctl-638.sh + cargo build --release first" >&2; exit 1; }
done

echo "==> Stopping v1.0.1 test daemon if active (avoid observation overlap)"
systemctl stop asusd-test.service 2>/dev/null || true

echo "==> Installing 6.3.8 binaries"
install -m 755 "$BIN_ASUSD"   /usr/local/sbin/asusd-638
install -m 755 "$BIN_ASUSCTL" /usr/local/bin/asusctl-638

echo "==> Writing test systemd unit → /etc/systemd/system/asusd-638-test.service"
sed -e 's|ExecStart=/usr/bin/asusd|ExecStart=/usr/local/sbin/asusd-638|' \
    -e 's|Description=ASUS Notebook Control|Description=ASUS Notebook Control (6.3.8 test)|' \
    "$SVC_SRC" > /etc/systemd/system/asusd-638-test.service
chmod 644 /etc/systemd/system/asusd-638-test.service

echo "==> Writing dbus policy → /etc/dbus-1/system.d/asusd-638-test.conf"
install -m 644 "$DBUS_SRC" /etc/dbus-1/system.d/asusd-638-test.conf

echo "==> Reloading systemd + dbus"
systemctl daemon-reload
systemctl reload dbus

echo "==> Starting asusd-638-test.service"
systemctl start asusd-638-test.service
sleep 2

if systemctl is-active --quiet asusd-638-test.service; then
    echo "  active ✓"
else
    echo "  FAILED — journalctl -u asusd-638-test.service --no-pager -n 40:" >&2
    journalctl -u asusd-638-test.service --no-pager -n 40 >&2
    exit 1
fi

echo "==> 6.3.8 daemon bus name (should be xyz.ljones.Asusd):"
gdbus introspect --system --dest xyz.ljones.Asusd --object-path /xyz/ljones/Asusd 2>&1 | head -3 || \
    echo "  (introspect failed — that's data too, record it)"

echo "==> Done. Use asusctl-638 (not system asusctl) to talk to this daemon."
