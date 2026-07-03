# Phase 2b Task 6 — End-to-End Verification Log

**Date:** 2026-07-03  
**Branch:** phase2b/task6-exit-report  
**Hardware:** ASUS TUF Gaming A15 FA507NV, Ubuntu 22.04, kernel 6.8.0-124-generic

---

## Step 1: Clean slate

```
sudo bash scripts/phase2b-teardown-debs.sh
```

Result: all four packages purged. `battery-charge-threshold.service` restored
to active+enabled by asusctl postrm. NVIDIA driver survived (core kernel
module still loaded).

**Teardown script incident:** first run included `apt-get autoremove -y` which
removed NVIDIA peripheral packages (nvidia-dkms-580, nvidia-settings, etc.)
that were marked auto-installed. Fix applied: removed `apt-get autoremove` from
`scripts/phase2b-teardown-debs.sh`. NVIDIA packages reinstalled and marked
manual via `apt-mark manual`. Core driver remained functional throughout.

---

## Step 2: Fresh install — all four packages

```
sudo dpkg -i \
    packages/asus-backlight-fix/build/asus-backlight-fix_1.0~jammy1_all.deb \
    packages/asusctl/build/asusctl_6.3.8-1~jammy1_amd64.deb \
    packages/supergfxctl/build/supergfxctl_5.2.7-1~jammy1_amd64.deb \
    packages/asusctl-suite/build/asusctl-suite_1.0~jammy1_all.deb
```

**preinst / postinst output (key lines):**
```
asusctl: stopping existing battery-charge-threshold.service
asus-backlight-fix: activated (FA507NV-family hardware detected). Reboot to apply.
supergfxctl: nvidia-prime is installed. [coexistence warning]
Created symlink .../asus-shutdown.service
Created symlink .../supergfxd.service
```

---

## Step 3: Post-install state

| Check | Result |
|---|---|
| `asusd.service` active | active |
| `supergfxd.service` active | active |
| `battery-charge-threshold.service` active | inactive |
| `battery-charge-threshold.service` enabled | disabled |
| `/etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf` | present |
| `99-nvidia-ac.rules` in `/lib/udev/rules.d/` | ABSENT |

---

## Step 4: Functional sanity

| Command | sysfs result |
|---|---|
| `asusctl profile set Balanced` | `throttle_thermal_policy` = 0 |
| `asusctl leds set med` | `kbd_backlight/brightness` = 2 |
| `asusctl battery limit 80` | `charge_control_end_threshold` = 80 |
| `supergfxctl -g` | Hybrid |

---

## Step 5: Purge round-trip

```
sudo bash scripts/phase2b-teardown-debs.sh
```

| Check | Result |
|---|---|
| `battery-charge-threshold.service` active | active |
| `battery-charge-threshold.service` enabled | enabled |
| `which asusctl` | PASS: absent |
| `which supergfxctl` | PASS: absent |
| `/etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf` | PASS: absent |
| `/etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf.disabled` | PASS: absent |
| `/var/lib/asusctl/` | PASS: absent |
| `/etc/asusd/` | PASS: absent |

---

## Step 6: Pre-flight snapshot diff

| Key | Result |
|---|---|
| `throttle_thermal_policy` | OK (matches snapshot) |
| `charge_control_end_threshold` | OK |
| `gpu_mux_mode` | OK |
| `/proc/cmdline` | OK |
| `/etc/modprobe.d/nvidia-custom.conf` | OK |

All 5 checks byte-identical to pre-flight snapshot. ✓

---

**Verdict: PASS. GO for Phase 2c.**
