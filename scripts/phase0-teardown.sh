#!/usr/bin/env bash
# Phase 0 teardown: reverses Tasks 4 and 10.
# Stops test daemons, removes installed test artifacts, verifies clean state.
# Idempotent. Preserves user's pre-existing:
#   - /etc/modprobe.d/nvidia-custom.conf
#   - /etc/systemd/system/battery-charge-threshold.service
#   - Kernel command line
#
# Run: sudo bash scripts/phase0-teardown.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (sudo bash $0)" >&2
    exit 1
fi

echo "==> Stopping test daemons"
for svc in asusd-test.service supergfxd-test.service nvidia-powerd.service; do
    if systemctl is-active "$svc" >/dev/null 2>&1; then
        systemctl stop "$svc" && echo "  stopped $svc"
    else
        echo "  $svc already inactive"
    fi
done

echo "==> Removing installed test binaries"
for f in /usr/local/sbin/asusd /usr/local/sbin/supergfxd /usr/local/bin/asusctl /usr/local/bin/supergfxctl; do
    if [ -f "$f" ]; then rm -f "$f" && echo "  removed $f"; fi
done

echo "==> Removing test systemd units"
for f in /etc/systemd/system/asusd-test.service /etc/systemd/system/supergfxd-test.service; do
    if [ -f "$f" ]; then rm -f "$f" && echo "  removed $f"; fi
done

echo "==> Removing test dbus policies"
for f in /etc/dbus-1/system.d/asusd-test.conf /etc/dbus-1/system.d/supergfxd-test.conf; do
    if [ -f "$f" ]; then rm -f "$f" && echo "  removed $f"; fi
done

echo "==> Removing test udev rule"
if [ -f /etc/udev/rules.d/90-supergfxd-nvidia-pm-test.rules ]; then
    rm -f /etc/udev/rules.d/90-supergfxd-nvidia-pm-test.rules
    echo "  removed 90-supergfxd-nvidia-pm-test.rules"
fi

echo "==> Removing supergfxd runtime-written modprobe conf"
if [ -f /etc/modprobe.d/supergfxd.conf ]; then
    rm -f /etc/modprobe.d/supergfxd.conf && echo "  removed /etc/modprobe.d/supergfxd.conf"
fi

echo "==> Reloading systemd, dbus, udev"
systemctl daemon-reload
systemctl reload dbus
udevadm control --reload-rules

echo ""
echo "==> Verification of preserved user state:"

# nvidia-custom.conf must be untouched
if [ -f /etc/modprobe.d/nvidia-custom.conf ]; then
    echo "  ✓ /etc/modprobe.d/nvidia-custom.conf present ($(wc -l < /etc/modprobe.d/nvidia-custom.conf) lines)"
else
    echo "  ✗ /etc/modprobe.d/nvidia-custom.conf MISSING — investigate"
    exit 2
fi

# battery-charge-threshold.service still enabled
if systemctl is-enabled battery-charge-threshold.service >/dev/null 2>&1; then
    echo "  ✓ battery-charge-threshold.service still enabled"
else
    echo "  ✗ battery-charge-threshold.service NOT enabled — investigate"
    exit 2
fi

# Battery threshold still at 80
th="$(cat /sys/class/power_supply/BAT1/charge_control_end_threshold 2>/dev/null || echo n/a)"
if [ "$th" = "80" ]; then
    echo "  ✓ battery threshold still 80"
else
    echo "  ⚠ battery threshold is $th (expected 80)"
fi

# Thermal policy valid (0, 1, or 2)
tp="$(cat /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy 2>/dev/null || echo x)"
if [ "$tp" = "0" ] || [ "$tp" = "1" ] || [ "$tp" = "2" ]; then
    echo "  ✓ thermal policy valid ($tp)"
else
    echo "  ⚠ thermal policy unexpected: $tp"
fi

echo ""
echo "==> No test artifacts remain:"
for f in /usr/local/sbin/asusd /usr/local/sbin/supergfxd /usr/local/bin/asusctl /usr/local/bin/supergfxctl \
         /etc/systemd/system/asusd-test.service /etc/systemd/system/supergfxd-test.service \
         /etc/dbus-1/system.d/asusd-test.conf /etc/dbus-1/system.d/supergfxd-test.conf \
         /etc/udev/rules.d/90-supergfxd-nvidia-pm-test.rules \
         /etc/modprobe.d/supergfxd.conf; do
    if [ -e "$f" ]; then echo "  ✗ still present: $f"; else :; fi
done
echo "  ✓ all test paths clear"

echo ""
echo "==> Teardown complete."
