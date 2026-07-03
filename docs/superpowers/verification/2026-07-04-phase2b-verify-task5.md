# Phase 2b Task 5 — asusctl-suite.deb Verification Report

**Date:** 2026-07-03  
**Branch:** phase2b/task5-asusctl-suite  
**Package:** `asusctl-suite_1.0~jammy1_all.deb`  
**Hardware:** ASUS TUF Gaming A15 FA507NV, Ubuntu 22.04, kernel 6.8.0-124-generic

---

## Build

**Source format:** `3.0 (native)` — correct for a meta-package with no upstream source.  
**Version:** `1.0~jammy1` (native packages carry no package-revision suffix).  
**Binary build:** pbuilder (no Cargo — pbuilder fully functional for this package).  
Build time: 17 seconds. Output: `asusctl-suite_1.0~jammy1_all.deb` (1.5 KB).

---

## Lintian

```
W: asusctl-suite: debian-changelog-has-wrong-day-of-week 2026-07-03 is a Friday
```

No errors. Day-of-week cosmetic warning only.

---

## Install Verification

**Pre-requisites installed first:**
```
sudo dpkg -i asus-backlight-fix_1.0~jammy1_all.deb \
             asusctl_6.3.8-1~jammy1_amd64.deb \
             supergfxctl_5.2.7-1~jammy1_amd64.deb
```

All three preinst/postinst scripts ran correctly (backlight activated, battery
service stopped, nvidia-prime warning printed).

**Meta-package install:**
```
sudo dpkg -i asusctl-suite_1.0~jammy1_all.deb
```
Clean install, no postinst (meta-package has none).

**Post-install state:**

| Package | Version | Installed |
|---|---|---|
| `asus-backlight-fix` | 1.0~jammy1 | ii |
| `asusctl` | 6.3.8-1~jammy1 | ii |
| `supergfxctl` | 5.2.7-1~jammy1 | ii |
| `asusctl-suite` | 1.0~jammy1 | ii |

**`apt-cache depends asusctl-suite` output:**
```
asusctl-suite
  Depends: asusctl
  Depends: supergfxctl
  Recommends: asus-backlight-fix
```

Dependency structure matches spec. ✓

---

**Verdict: PASS.** Meta-package builds cleanly in pbuilder, installs, and pulls
the correct dependency tree. `sudo apt install asusctl-suite` is ready to use
once these packages are in a PPA.
