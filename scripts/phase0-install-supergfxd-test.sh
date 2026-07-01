#!/usr/bin/env bash
# Phase 0 helper: installs supergfxd + supergfxctl from upstream/supergfxctl/target/release
# into /usr/local plus a test-only systemd unit and dbus policy. Idempotent.
#
# Deliberately SKIPS 99-nvidia-ac.rules — that rule starts/stops nvidia-powerd on AC
# transitions, which is precisely the trigger for nv_acpi_powersource_hotplug_event
# lockups on FA507NV. Installing it here would arm the documented crash pattern.
#
# Run: sudo bash scripts/phase0-install-supergfxd-test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="$REPO_ROOT/upstream/supergfxctl"
BIN_D="$UPSTREAM/target/release/supergfxd"
BIN_CTL="$UPSTREAM/target/release/supergfxctl"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (sudo bash $0)" >&2
    exit 1
fi

for f in "$BIN_D" "$BIN_CTL" "$UPSTREAM/data/supergfxd.service" "$UPSTREAM/data/org.supergfxctl.Daemon.conf"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing $f — run Task 9 first" >&2
        exit 1
    fi
done

echo "==> Installing binaries to /usr/local"
install -m 755 "$BIN_D" /usr/local/sbin/supergfxd
install -m 755 "$BIN_CTL" /usr/local/bin/supergfxctl

echo "==> Installing test systemd unit → /etc/systemd/system/supergfxd-test.service"
sed 's|ExecStart=/usr/bin/supergfxd|ExecStart=/usr/local/sbin/supergfxd|' \
    "$UPSTREAM/data/supergfxd.service" > /etc/systemd/system/supergfxd-test.service
chmod 644 /etc/systemd/system/supergfxd-test.service

echo "==> Installing dbus policy → /etc/dbus-1/system.d/supergfxd-test.conf"
install -m 644 "$UPSTREAM/data/org.supergfxctl.Daemon.conf" /etc/dbus-1/system.d/supergfxd-test.conf

echo "==> INSTALLING nvidia-pm udev rule (runtime PM on driver bind)"
install -m 644 "$UPSTREAM/data/90-supergfxd-nvidia-pm.rules" /etc/udev/rules.d/90-supergfxd-nvidia-pm-test.rules

echo "==> SKIPPING 99-nvidia-ac.rules"
echo "    Reason: this rule restarts nvidia-powerd on every AC power-state change,"
echo "    which is the documented trigger for nv_acpi_powersource_hotplug_event"
echo "    lockups on FA507NV. Do not install without mitigating the ACPI bug."

echo "==> Reloading systemd, udev, dbus"
systemctl daemon-reload
udevadm control --reload-rules
systemctl reload dbus

echo "==> Starting supergfxd-test.service"
systemctl start supergfxd-test.service
sleep 2

echo "==> Service status:"
systemctl is-active supergfxd-test.service && echo "  active ✓" || { echo "  FAILED — see 'journalctl -u supergfxd-test' for details"; exit 1; }

echo "==> Installed files:"
ls -la /usr/local/sbin/supergfxd /usr/local/bin/supergfxctl \
       /etc/systemd/system/supergfxd-test.service \
       /etc/dbus-1/system.d/supergfxd-test.conf \
       /etc/udev/rules.d/90-supergfxd-nvidia-pm-test.rules

echo "==> Done. Verify with: supergfxctl -g  (should print current GPU mode)"
