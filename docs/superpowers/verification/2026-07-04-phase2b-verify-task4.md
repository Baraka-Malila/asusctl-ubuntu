# Phase 2b Task 4 — supergfxctl.deb Verification Report

**Date:** 2026-07-03  
**Branch:** phase2b/task4-supergfxctl-deb  
**Package:** `supergfxctl_5.2.7-1~jammy1_amd64.deb`  
**Hardware:** ASUS TUF Gaming A15 FA507NV, Ubuntu 22.04, kernel 6.8.0-124-generic

---

## Build

**Source package:** `dpkg-source -b` via `scripts/build-source-package.sh supergfxctl`  
Patch applied cleanly:
- `0001-drop-99-nvidia-ac-rules.patch`

**Binary build:** `scripts/build-deb-pbuilder.sh supergfxctl --direct` (host build)  
Cargo compile time: ~52 seconds (warm cache)  
Output: `supergfxctl_5.2.7-1~jammy1_amd64.deb` (1.5 MB)

Note: pbuilder satisfies `rustc (>= 1.64)` and `cargo (>= 0.66)` from Jammy repos, but
`cargo build` needs network to download crates and pbuilder disables it during build. Same
root cause as Task 3 — `--direct` flag used. Fix deferred to Phase 2c (vendor tarball).

---

## Lintian

```
W: supergfxctl: debian-changelog-has-wrong-day-of-week 2026-07-03 is a Friday
W: supergfxctl: no-manual-page usr/bin/supergfxctl
W: supergfxctl: no-manual-page usr/bin/supergfxd
W: supergfxctl: systemd-service-file-refers-to-unusual-wantedby-target getty.target
```

No errors. `getty.target` in `[Install]` is upstream's choice — not modified.

---

## Install Verification

**Install command:** `sudo dpkg -i supergfxctl_5.2.7-1~jammy1_amd64.deb`

**postinst output:**
```
supergfxctl: nvidia-prime is installed. supergfxctl and
  nvidia-prime can coexist but may confuse each other on GPU
  mode switches. Prefer supergfxctl for mode switching.
Created symlink /etc/systemd/system/getty.target.wants/supergfxd.service
```

**Post-install state:**

| Check | Result |
|---|---|
| `supergfxd.service` active | active |
| `supergfxd.service` enabled | enabled |
| `supergfxctl -g` | Hybrid |
| `99-nvidia-ac.rules` in `/lib/udev/rules.d/` | ABSENT ✓ |
| `/usr/bin/supergfxd` | present |
| `/usr/bin/supergfxctl` | present |
| `/lib/udev/rules.d/90-supergfxd-nvidia-pm.rules` | present |
| `/lib/systemd/system/supergfxd.service` | present |

---

## Purge Rollback

**Command:** `sudo apt-get purge -y supergfxctl`

**Post-purge state:**

| Check | Result |
|---|---|
| `supergfxd.service` active | inactive |
| `which supergfxctl` | not found |
| `/lib/udev/rules.d/90-supergfxd-nvidia-pm.rules` | absent |

Full round-trip clean. ✓

---

**Verdict: PASS.** Package builds, installs, functions, and purges cleanly on FA507NV.
The crash rule (`99-nvidia-ac.rules`) is confirmed absent post-install.
