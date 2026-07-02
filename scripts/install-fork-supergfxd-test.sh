#!/usr/bin/env bash
# Phase 1 test install for our fork's supergfxd. NEVER installs upstream's
# 99-nvidia-ac.rules — that rule crashes the NVIDIA driver on FA507NV
# (Phase 0 finding). Task 7 lands a safe replacement; until then, no rule.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FORK="$REPO_ROOT/fork/supergfxctl"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (sudo bash $0)" >&2
    exit 1
fi

for f in "$FORK/target/release/supergfxd" "$FORK/target/release/supergfxctl" \
         "$FORK/data/supergfxd.service" "$FORK/data/org.supergfxctl.Daemon.conf"; do
    [ -f "$f" ] || { echo "ERROR: missing $f — run scripts/build-fork-supergfxctl.sh first" >&2; exit 1; }
done

echo "==> Installing binaries"
install -m 755 "$FORK/target/release/supergfxd"   /usr/local/sbin/supergfxd
install -m 755 "$FORK/target/release/supergfxctl" /usr/local/bin/supergfxctl

echo "==> Installing test systemd unit → /etc/systemd/system/supergfxd-test.service"
sed 's|ExecStart=/usr/bin/supergfxd|ExecStart=/usr/local/sbin/supergfxd|' \
    "$FORK/data/supergfxd.service" > /etc/systemd/system/supergfxd-test.service
chmod 644 /etc/systemd/system/supergfxd-test.service

echo "==> Installing dbus policy → /etc/dbus-1/system.d/supergfxd-test.conf"
install -m 644 "$FORK/data/org.supergfxctl.Daemon.conf" /etc/dbus-1/system.d/supergfxd-test.conf

echo "==> Deliberately NOT installing 99-nvidia-ac.rules (Phase 0 crash trigger). Task 7 replaces."

echo "==> Reloading systemd + dbus"
systemctl daemon-reload
systemctl reload dbus

echo "==> Starting supergfxd-test.service"
systemctl start supergfxd-test.service
sleep 2

if systemctl is-active --quiet supergfxd-test.service; then
    echo "  active ✓"
else
    echo "  FAILED — journalctl -u supergfxd-test.service --no-pager -n 40:" >&2
    journalctl -u supergfxd-test.service --no-pager -n 40 >&2
    exit 1
fi

echo "==> Done."
