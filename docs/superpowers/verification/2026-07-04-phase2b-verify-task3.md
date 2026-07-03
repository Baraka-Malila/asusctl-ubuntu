# Phase 2b Task 3 — asusctl.deb Verification Report

**Date:** 2026-07-03  
**Branch:** phase2b/task2-asus-backlight-fix (filing here before the Task 3 PR branch is cut)  
**Package:** `asusctl_6.3.8-1~jammy1_amd64.deb`  
**Hardware:** ASUS TUF Gaming A15 FA507NV, Ubuntu 22.04, kernel 6.8.0-124-generic

---

## Build

**Source package:** `dpkg-source -b` via `scripts/build-source-package.sh asusctl`  
All three patches applied cleanly:
- `0001-power-source-sysfs-watcher.patch`
- `0002-kbd-brightness-on-power.patch`
- `0003-gpu-mode-per-power.patch`

**Binary build:** `scripts/build-deb-pbuilder.sh asusctl --direct` (host build, see Known Issues)  
Cargo compile time: ~71 seconds (warm cache)  
Output: `asusctl_6.3.8-1~jammy1_amd64.deb` (3.3 MB)

---

## Lintian

```
W: asusctl: debian-changelog-has-wrong-day-of-week 2026-07-04 is a Saturday
W: asusctl: maintainer-script-calls-systemctl [postrm:7]
W: asusctl: maintainer-script-calls-systemctl [postrm:8]
W: asusctl: maintainer-script-calls-systemctl [preinst:8]
W: asusctl: maintainer-script-calls-systemctl [preinst:9]
W: asusctl: no-manual-page usr/bin/asusctl
W: asusctl: no-manual-page usr/sbin/asusd
```

No errors. Warnings are accepted:
- Day-of-week: cosmetic; fix in next changelog revision
- `maintainer-script-calls-systemctl`: required — we manage a pre-existing system service (`battery-charge-threshold.service`) that `dh_installsystemd` cannot handle
- No man pages: upstream doesn't ship them; deferral confirmed in design spec

---

## Install Verification

**Pre-install state:**
- `battery-charge-threshold.service`: active, enabled

**Install command:** `sudo dpkg -i asusctl_6.3.8-1~jammy1_amd64.deb`

**preinst output:**
```
asusctl: stopping existing battery-charge-threshold.service (asusd owns charge_control_end_threshold from now on).
Removed /etc/systemd/system/multi-user.target.wants/battery-charge-threshold.service.
```

**Post-install state:**

| Check | Result |
|---|---|
| `asusd.service` active | active |
| `asusd.service` enabled | static (D-Bus activated; no [Install] section in upstream unit — expected) |
| `battery-charge-threshold.service` active | inactive |
| `battery-charge-threshold.service` enabled | disabled |
| `/var/lib/asusctl/batsvc-was-active` exists | yes |
| `/usr/bin/asusd` | present |
| `/usr/bin/asusctl` | present |
| `/usr/libexec/asusctl/asus-shutdown` | present |

---

## Functional Tests

```
asusctl profile set Balanced
→ /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy = 0  ✓

asusctl leds set med
→ /sys/class/leds/asus::kbd_backlight/brightness = 2  ✓

asusctl battery limit 80
→ /sys/class/power_supply/BAT1/charge_control_end_threshold = 80  ✓
```

---

## Purge Rollback

**Command:** `sudo apt-get purge -y asusctl`

**postrm output:**
```
asusctl: restoring battery-charge-threshold.service to enabled+active state.
```

**Post-purge state:**

| Check | Result |
|---|---|
| `battery-charge-threshold.service` active | active |
| `battery-charge-threshold.service` enabled | enabled |
| `/var/lib/asusctl/` | absent |
| `/etc/asusd/` | absent |
| `which asusctl` | not found |
| `which asusd` | not found |

Full round-trip clean. ✓

---

## Known Issues / Follow-ups

1. **pbuilder + rustc version:** Jammy's chroot has rustc 1.75.0; asusctl requires 1.82+. Used `--direct` (host build) for Phase 2b. Phase 2c (PPA) must resolve this via: (a) offline vendor tarball in the source package, or (b) a pbuilder hook that installs rustup before build.

2. **`rog_simulators` excluded:** Added `--exclude rog_simulators` to `debian/rules`'s `cargo build` call. The `rog_simulators` crate depends on `uhid-virt 0.0.8` which fails to compile against kernel 6.8 headers (`hid_report_type_HID_*` renamed to `uhid_report_type_UHID_*`). We don't ship the simulator binary, so excluding it is correct.

3. **`asusd` in `/usr/bin/`:** Upstream `asusd.service` hardcodes `ExecStart=/usr/bin/asusd`. Ubuntu 22.04 does not have `usrmerge` (no `/usr/sbin → /usr/bin` symlink), so we install `asusd` to `usr/bin/` (not `usr/sbin/`). This is correct for matching the upstream service file.

4. **Changelog day-of-week:** `2026-07-04` was given as Friday in the plan but is actually Saturday. Low-priority fix.

---

**Verdict: PASS.** Package builds, installs, functions, and purges cleanly on FA507NV.
