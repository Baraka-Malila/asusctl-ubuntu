#!/usr/bin/env bash
# Phase 2b: capture FA507NV pre-Phase-2b state to /var/lib/asus-phase1-fork/phase2b.
# Persistent (not tmpfs); Task 6 diffs against this at the end.
set -euo pipefail
SNAP=/var/lib/asus-phase1-fork/phase2b
# Use sudo -n (non-interactive) — expects sudo to work without prompt (either
# already-cached credential, NOPASSWD, or password piped via `sudo -S` from a
# wrapper). If it fails, caller should re-run with `echo <pw> | sudo -S bash <this>`.
if ! sudo -n mkdir -p "$SNAP" 2>/dev/null; then
    echo "ERROR: cannot create $SNAP as root. Re-run under sudo or pipe password:" >&2
    echo "  echo '<sudo-password>' | sudo -S bash $0" >&2
    exit 1
fi
sudo -n chown "$USER:$USER" "$SNAP"
cat /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy > "$SNAP/thermal" 2>/dev/null || true
cat /sys/class/power_supply/BAT1/charge_control_end_threshold > "$SNAP/charge"  2>/dev/null || true
cat /sys/class/leds/asus::kbd_backlight/brightness            > "$SNAP/kbd"     2>/dev/null || true
cat /sys/devices/platform/asus-nb-wmi/gpu_mux_mode            > "$SNAP/gpu_mux" 2>/dev/null || true
cat /proc/cmdline                                             > "$SNAP/cmdline"
cp  /etc/modprobe.d/nvidia-custom.conf                          "$SNAP/" 2>/dev/null || true
systemctl is-enabled battery-charge-threshold.service          > "$SNAP/batsvc.enabled" 2>&1 || true
systemctl is-active  battery-charge-threshold.service          > "$SNAP/batsvc.active"  2>&1 || true
echo "==> Snapshot at $SNAP"
ls -la "$SNAP"
