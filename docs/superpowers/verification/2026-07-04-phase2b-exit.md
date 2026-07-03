# Phase 2b Exit Report

**Date:** 2026-07-03  
**Branch:** phase2b/task6-exit-report  
**Hardware:** ASUS TUF Gaming A15 FA507NV, Ubuntu 22.04, kernel 6.8.0-124-generic

---

## Verdict: PASS — GO for Phase 2c

All four Debian packages build, install, and purge cleanly on Jammy. The full
end-to-end verification log is in `2026-07-04-phase2b-verify-task6.md`.

---

## Deliverables

| Package | Version | Size | Build mode |
|---|---|---|---|
| `asusctl_6.3.8-1~jammy1_amd64.deb` | 6.3.8-1~jammy1 | 3.2 MB | --direct (rustc 1.93 via rustup) |
| `supergfxctl_5.2.7-1~jammy1_amd64.deb` | 5.2.7-1~jammy1 | 1.5 MB | --direct (rustc 1.93 via rustup) |
| `asus-backlight-fix_1.0~jammy1_all.deb` | 1.0~jammy1 | 2.6 KB | pbuilder |
| `asusctl-suite_1.0~jammy1_all.deb` | 1.0~jammy1 | 1.6 KB | pbuilder |

All four packages are lintian-clean and install/purge without errors.

---

## What Phase 2b Delivered

- `asusd` (ASUS system daemon) packaged and running as `asusd.service`
- `supergfxd` (GPU mode daemon) packaged and running as `supergfxd.service`
- `asusctl` and `supergfxctl` CLIs installed to `/usr/bin/`
- FA507NV backlight fix packaged with hardware detection in `postinst`
- `asusctl-suite` meta-package: `sudo apt install asusctl-suite` is the user
  entry point
- `battery-charge-threshold.service` integrated: stopped on install,
  restored on purge — no data loss
- `99-nvidia-ac.rules` excluded from `supergfxctl` package (patch applied) —
  coexists safely with Ubuntu's `nvidia-prime`
- Generic per-package build script (`scripts/build-deb-pbuilder.sh`) with
  `--direct` mode for Rust packages

---

## Deferrals Honored

| Item | Deferred to |
|---|---|
| `cargo vendor` / offline Rust build | Phase 2c (required for Launchpad) |
| Launchpad PPA upload | Phase 2c |
| GitHub Actions CI | Phase 2c |
| `install.md` / `troubleshoot.md` | Phase 2c |
| GTK4/libadwaita GUI | Phase 2b.5+ (post Phase 2c) |

---

## Pre-flight vs Post-purge Diff

| sysfs / config key | Pre-flight | Post-purge |
|---|---|---|
| `throttle_thermal_policy` | matches | matches |
| `charge_control_end_threshold` | matches | matches |
| `gpu_mux_mode` | matches | matches |
| `/proc/cmdline` | matches | matches |
| `/etc/modprobe.d/nvidia-custom.conf` | matches | matches |

All 5 keys byte-identical. Machine state is fully restored after purge.

---

## Known Follow-ups (Phase 2c Scope)

1. **Rust packages need `cargo vendor`** — `dpkg-buildpackage` with a vendored
   `Cargo.lock` + `vendor/` tarball is the only way to build offline in pbuilder
   or on Launchpad. The `--direct` mode works locally but cannot run on
   Launchpad's buildds (no outbound network).

2. **Jammy rustc 1.75 < asusctl `rust-version = "1.82"`** — pbuilder chroot
   cannot build asusctl today. Workaround options for Phase 2c: bump
   Build-Depends to `rustc (>= 1.82)` + provide via PPA, or lower
   `rust-version` in our patched tree.

3. **`apt-get autoremove` removed NVIDIA peripherals** — removed from teardown
   script; NVIDIA packages reinstalled and marked manual. Root cause: Ubuntu
   marks many NVIDIA packages auto-installed even though they are required.
   No action needed in packages; documented for future teardown tooling.

4. **Minor NVML version skew (580.167→580.173)** — non-critical, resolves
   after next kernel driver package update.

---

## Phase 2c Entry Criteria

- [ ] User merges PR #21 (this branch)
- [ ] User tags `phase2b-v0.1-packaging` on `main`
- [ ] Phase 2c branch started from that tag
