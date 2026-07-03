# Phase 2b — Debian packaging (core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce four Debian source packages (`asusctl`, `supergfxctl`, `asus-backlight-fix`, `asusctl-suite`) that build clean via `pbuilder` on Jammy and install cleanly on FA507NV, delivering `sudo apt install asusctl-suite` as the user entry point.

**Architecture:** `3.0 (quilt)` source packages. Upstream `.orig.tar.xz` fetched from vendor tags; our `patches/*/series` is copied verbatim into `debian/patches/series` at source-build time (single source of truth). Meta-package pulls the three functional packages. Backlight fix is a separate hardware-gated package (avoids `update-initramfs -u` on unaffected hardware). Reproducibility comes from `pbuilder` chroot builds — same mechanism Launchpad uses in Phase 2c.

**Tech Stack:** debhelper compat 12, dh-quilt, cargo ≥ 0.66 / rustc ≥ 1.82 (Jammy defaults are older; build-depends pull them), pbuilder, dpkg-buildpackage, lintian. Ubuntu 22.04 Jammy host + FA507NV hardware.

## Global Constraints

- Fork base tags (from Phase 2a exit): asusctl `6.3.8`, supergfxctl `5.2.7`. Match these exactly in `debian/changelog` and `.orig.tar.xz` filenames.
- Version scheme: `<upstream>-<pkg-rev>~<distro><distro-rev>`. First iterations: `6.3.8-1~jammy1`, `5.2.7-1~jammy1`, `1.0-1~jammy1` (for our own two packages).
- Source format `3.0 (quilt)` — mandatory (Section 4 of spec). `debian/source/format` must contain exactly `3.0 (quilt)`.
- Enumerated `debian/*.install` — never `data/*.rules` globs (spec §7, and it's the whole point of Task 7 in Phase 1).
- Existing patch series is the source of truth. **Never edit** `debian/patches/*` by hand — those files are regenerated from `patches/asusctl/series` and `patches/supergfxctl/series` at each source-package build.
- PR-and-merge workflow (memory: `feedback_workflow.md`). Feature branch per task: `phase2b/task-N-<slug>`. User merges every PR.
- 300-line limit applies to code/scripts/systemd units/config files (CLAUDE.md rule 1); `debian/control` and `debian/rules` may exceed. Plans, specs, and verification reports may exceed (memory: `feedback_file_length_scope.md`).
- Real hardware only for verification: FA507NV. No VMs / no emulators.
- Preserve pre-Phase-2b state: `/etc/modprobe.d/nvidia-custom.conf`, kernel cmdline, `battery-charge-threshold.service` enable-state (record before task 2, restore after each verification).
- FA507NV pre-flight snapshot goes to `/var/lib/asus-phase1-fork/phase2b/` (persistent across reboots — `/tmp` gets wiped on Ubuntu 22.04).
- Every task ends with `gh pr create` + reference to this plan + reference to the design spec `docs/superpowers/specs/2026-07-04-phase2b-packaging-design.md`.

---

## Files & Structure

**Created / committed:**

- `pbuilderrc` — pbuilder config for Jammy target
- `.gitignore` — added `packages/*/build/`, `packages/*/*.orig.tar.xz`, `packages/*/*.debian.tar.xz`, `packages/*/*.dsc`, `packages/*/*.buildinfo`, `packages/*/*.changes`, `/var/lib/asus-phase1-fork/phase2b/`
- `scripts/build-source-package.sh` — generic per-package source builder (fetch tarball + copy patches + `dpkg-source -b`)
- `scripts/build-deb-pbuilder.sh` — generic per-package pbuilder binary build
- `scripts/build-all-debs.sh` — orchestrator
- `scripts/phase2b-preflight.sh` — captures the pre-flight snapshot
- `scripts/phase2b-teardown-debs.sh` — clean removal of the four packages with dependency-safe order
- `packages/asusctl/debian/` — full `debian/` tree per spec §6
- `packages/supergfxctl/debian/` — full `debian/` tree per spec §7
- `packages/asus-backlight-fix/debian/` + `packages/asus-backlight-fix/files/asusctl-fa507nv-backlight-fix.conf.disabled`
- `packages/asusctl-suite/debian/` — meta per spec §9
- `docs/superpowers/verification/2026-07-04-phase2b-verify-taskN.md` — one per task

**Gitignored:**

- `packages/*/build/` (per-pkg pbuilder outputs)
- `upstream/` (already ignored)
- `fork/` (already ignored)

---

## Pre-flight snapshot

Handled by Task 1 (build tooling includes the `scripts/phase2b-preflight.sh` helper). Snapshot at `/var/lib/asus-phase1-fork/phase2b/` captures:

- `throttle_thermal_policy`, `charge_control_end_threshold` (BAT1), `kbd_backlight/brightness`, `gpu_mux_mode`, `/proc/cmdline`, `nvidia-custom.conf` (copied), `battery-charge-threshold.service` enable + active state

Task 6 (final verify) diffs the current values against this snapshot.

---

### Task 1: Build tooling — pbuilder + generic scripts

**Files:**
- Create: `pbuilderrc`
- Create: `scripts/build-source-package.sh`
- Create: `scripts/build-deb-pbuilder.sh`
- Create: `scripts/build-all-debs.sh`
- Create: `scripts/phase2b-preflight.sh`
- Create: `scripts/phase2b-teardown-debs.sh`
- Modify: `.gitignore`

**Consumes:** Existing `patches/asusctl/series`, `patches/supergfxctl/series`, and the fork trees under `fork/*/`.

**Produces:** Three shell helpers usable by tasks 2-6. Every subsequent task depends on these existing.

**Interfaces:**
- `build-source-package.sh <pkgname>` — reads `packages/<pkgname>/upstream.env` for TARBALL_URL and UPSTREAM_TAG, extracts to a temp dir, copies patches/<pkgname>/series and .patch files into `debian/patches/` (only when a `patches/<pkgname>/` dir exists), runs `dpkg-source -b`. Output lands in `packages/<pkgname>/build/`.
- `build-deb-pbuilder.sh <pkgname>` — runs `pbuilder build packages/<pkgname>/build/<pkg>_<ver>.dsc`. Output binary `.deb` in `packages/<pkgname>/build/`.
- `build-all-debs.sh` — orchestrator that runs source + binary build for the four packages in the right order.

- [ ] **Step 1: Install prerequisites**

```bash
echo '381011' | sudo -S apt-get update
echo '381011' | sudo -S apt-get install -y \
    debhelper devscripts dh-make dpkg-dev quilt pbuilder \
    lintian fakeroot dput
```

- [ ] **Step 2: Write `pbuilderrc`**

```
# Jammy pbuilder config for asusctl-ubuntu Phase 2b
DISTRIBUTION=jammy
COMPONENTS="main universe restricted multiverse"
MIRRORSITE=http://archive.ubuntu.com/ubuntu
OTHERMIRROR="deb http://archive.ubuntu.com/ubuntu jammy-updates main universe restricted multiverse"
BASETGZ=/var/cache/pbuilder/base-jammy.tgz
BUILDPLACE=/var/cache/pbuilder/build
BUILDRESULT=/var/cache/pbuilder/result
APTCACHE=/var/cache/pbuilder/aptcache
DEBBUILDOPTS="-b"
EXTRAPACKAGES="ca-certificates gnupg"
```

- [ ] **Step 3: Create the Jammy pbuilder base image**

```bash
echo '381011' | sudo -S pbuilder create --configfile pbuilderrc
```

Expected: takes 3-5 minutes on first run. Populates `/var/cache/pbuilder/base-jammy.tgz`. Rerun is idempotent (skip if the tgz exists).

- [ ] **Step 4: Write `scripts/build-source-package.sh`**

```bash
#!/usr/bin/env bash
# Phase 2b: generate a 3.0 (quilt) source package for one of our packages.
#   Usage: scripts/build-source-package.sh <pkgname>
#
# Requires packages/<pkgname>/upstream.env exporting:
#   TARBALL_URL   — where to fetch upstream .orig.tar.gz
#   UPSTREAM_TAG  — matches the version in debian/changelog
#   ORIG_NAME     — the .orig.tar.xz basename (without _<ver>.orig.tar.xz suffix)
# For packages with no upstream (asus-backlight-fix, asusctl-suite):
#   NO_UPSTREAM=1 — script skips tarball fetch, uses debian/ + files/ as-is
set -euo pipefail

PKGNAME="${1:?usage: $0 <pkgname>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$REPO_ROOT/packages/$PKGNAME"
BUILD_DIR="$PKG_DIR/build"
PATCHES_SRC="$REPO_ROOT/patches/$PKGNAME"

[ -f "$PKG_DIR/upstream.env" ] || { echo "ERROR: $PKG_DIR/upstream.env missing" >&2; exit 1; }
# shellcheck disable=SC1090
source "$PKG_DIR/upstream.env"

mkdir -p "$BUILD_DIR"

if [ "${NO_UPSTREAM:-0}" = "1" ]; then
    # Meta-packages / files-only packages: build source directly from packages/<pkg>/
    STAGE="$BUILD_DIR/stage"
    rm -rf "$STAGE" && mkdir -p "$STAGE"
    cp -a "$PKG_DIR/debian" "$STAGE/"
    [ -d "$PKG_DIR/files" ] && cp -a "$PKG_DIR/files" "$STAGE/"
    (cd "$BUILD_DIR" && dpkg-source -b stage)
    rm -rf "$STAGE"
    echo "==> Source package built for $PKGNAME (NO_UPSTREAM)"
    exit 0
fi

ORIG_TARBALL="$BUILD_DIR/${ORIG_NAME}_${UPSTREAM_TAG}.orig.tar.xz"
if [ ! -f "$ORIG_TARBALL" ]; then
    echo "==> Fetching $TARBALL_URL"
    TMPGZ=$(mktemp --suffix=.tar.gz)
    curl -fsSL "$TARBALL_URL" -o "$TMPGZ"
    # Recompress to .orig.tar.xz (Debian preference)
    gunzip -c "$TMPGZ" | xz -c > "$ORIG_TARBALL"
    rm -f "$TMPGZ"
fi

# Stage: extract tarball, drop in debian/, copy our patches/<pkg>/series into
# debian/patches/, build source package.
STAGE="$BUILD_DIR/stage"
rm -rf "$STAGE" && mkdir -p "$STAGE"
(cd "$STAGE" && tar --strip-components=1 -xf "$ORIG_TARBALL")
cp -a "$PKG_DIR/debian" "$STAGE/"

if [ -d "$PATCHES_SRC" ]; then
    mkdir -p "$STAGE/debian/patches"
    cp "$PATCHES_SRC"/*.patch "$STAGE/debian/patches/"
    cp "$PATCHES_SRC/series"  "$STAGE/debian/patches/series"
fi

(cd "$BUILD_DIR" && dpkg-source -b stage)
rm -rf "$STAGE"
echo "==> Source package built for $PKGNAME"
```

- [ ] **Step 5: Make it executable**

```bash
chmod +x scripts/build-source-package.sh
```

- [ ] **Step 6: Write `scripts/build-deb-pbuilder.sh`**

```bash
#!/usr/bin/env bash
# Phase 2b: build a binary .deb in a Jammy pbuilder chroot.
#   Usage: scripts/build-deb-pbuilder.sh <pkgname>
set -euo pipefail

PKGNAME="${1:?usage: $0 <pkgname>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/packages/$PKGNAME/build"
DSC=$(ls "$BUILD_DIR"/*.dsc 2>/dev/null | head -1)
[ -n "$DSC" ] || { echo "ERROR: no .dsc under $BUILD_DIR — run build-source-package.sh first" >&2; exit 1; }

echo "==> pbuilder build for $DSC"
echo '381011' | sudo -S pbuilder build --configfile "$REPO_ROOT/pbuilderrc" \
    --buildresult "$BUILD_DIR" "$DSC"

echo "==> Resulting artifacts in $BUILD_DIR:"
ls -la "$BUILD_DIR"/*.deb 2>&1
```

Make it executable: `chmod +x scripts/build-deb-pbuilder.sh`.

- [ ] **Step 7: Write `scripts/build-all-debs.sh`**

```bash
#!/usr/bin/env bash
# Phase 2b: build source + binary for all four packages in dependency order.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

for pkg in asus-backlight-fix asusctl supergfxctl asusctl-suite; do
    echo "===== $pkg ====="
    ./scripts/build-source-package.sh "$pkg"
    ./scripts/build-deb-pbuilder.sh   "$pkg"
done

echo "==> All four packages built. Artifacts:"
find packages/*/build -maxdepth 1 -name '*.deb'
```

Make it executable.

- [ ] **Step 8: Write `scripts/phase2b-preflight.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SNAP=/var/lib/asus-phase1-fork/phase2b
sudo mkdir -p "$SNAP" && sudo chown "$USER:$USER" "$SNAP"
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
```

Make it executable.

- [ ] **Step 9: Write `scripts/phase2b-teardown-debs.sh`**

```bash
#!/usr/bin/env bash
# Purge our four Debian packages in dependency-safe order (reverse-dep first).
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root" >&2; exit 1
fi
for pkg in asusctl-suite asus-backlight-fix asusctl supergfxctl; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        echo "==> Purging $pkg"
        apt-get purge -y "$pkg" || true
    fi
done
apt-get autoremove -y || true
echo "==> Done"
```

Make it executable.

- [ ] **Step 10: Update `.gitignore`**

Append:

```
# Phase 2b Debian build outputs
packages/*/build/
packages/*/*.orig.tar.xz
packages/*/*.debian.tar.xz
packages/*/*.dsc
packages/*/*.buildinfo
packages/*/*.changes
```

- [ ] **Step 11: Feature branch + commit + PR**

```bash
git checkout -b phase2b/task1-build-tooling
git add pbuilderrc scripts/build-source-package.sh scripts/build-deb-pbuilder.sh \
        scripts/build-all-debs.sh scripts/phase2b-preflight.sh scripts/phase2b-teardown-debs.sh \
        .gitignore
git commit -m "Phase 2b Task 1: pbuilder + generic per-package build scripts"
git push -u origin phase2b/task1-build-tooling
gh pr create --title "Phase 2b Task 1: build tooling" \
    --body "pbuilderrc for Jammy target; generic per-package source + binary build scripts consumed by tasks 2-6."
```

---

### Task 2: `asus-backlight-fix` package

**Files:**
- Create: `packages/asus-backlight-fix/upstream.env`
- Create: `packages/asus-backlight-fix/files/asusctl-fa507nv-backlight-fix.conf.disabled`
- Create: `packages/asus-backlight-fix/debian/changelog`
- Create: `packages/asus-backlight-fix/debian/control`
- Create: `packages/asus-backlight-fix/debian/copyright`
- Create: `packages/asus-backlight-fix/debian/rules`
- Create: `packages/asus-backlight-fix/debian/compat`
- Create: `packages/asus-backlight-fix/debian/source/format`
- Create: `packages/asus-backlight-fix/debian/asus-backlight-fix.install`
- Create: `packages/asus-backlight-fix/debian/asus-backlight-fix.postinst`
- Create: `packages/asus-backlight-fix/debian/asus-backlight-fix.postrm`
- Create: `docs/superpowers/verification/2026-07-04-phase2b-verify-task2.md`

**Consumes:** Task 1 build tooling.

**Produces:** `packages/asus-backlight-fix/build/asus-backlight-fix_1.0-1~jammy1_all.deb`. On install to matching hardware, blacklists `nvidia_wmi_ec_backlight` + regenerates initramfs.

**Interfaces:**
- Consumes: `build-source-package.sh` (via `NO_UPSTREAM=1`), `build-deb-pbuilder.sh`.
- Produces: `.deb` consumed by Task 5 (`asusctl-suite` Recommends).

- [ ] **Step 1: Run pre-flight snapshot before touching hardware**

```bash
./scripts/phase2b-preflight.sh
```

- [ ] **Step 2: Create `packages/asus-backlight-fix/upstream.env`**

```bash
# No upstream — this is our own package. Signals to build-source-package.sh.
NO_UPSTREAM=1
```

- [ ] **Step 3: Create the modprobe file to ship**

`packages/asus-backlight-fix/files/asusctl-fa507nv-backlight-fix.conf.disabled`:

```
# Blacklist NVIDIA WMI EC backlight shadow interface on FA507NV-family hardware.
# It races with amdgpu_bl1 (the real panel controller for eDP-1) inside
# gsd-power, causing the GNOME brightness slider to silently no-op ~half
# the time.
#
# This file is shipped as .disabled. The asus-backlight-fix postinst
# renames it to .conf and regenerates the initramfs only if the runtime
# hardware matches the FA507NV race pattern (both amdgpu_bl* and nvidia_0
# backlight interfaces present, nvidia_wmi_ec_backlight module loaded).
blacklist nvidia_wmi_ec_backlight
```

- [ ] **Step 4: Create `debian/changelog`**

Use `dch` from devscripts, or write by hand:

```
asus-backlight-fix (1.0-1~jammy1) jammy; urgency=medium

  * Phase 2b Task 2: initial packaging for the FA507NV-family
    backlight-shadow blacklist workaround.

 -- Baraka Malila <bmalila87@gmail.com>  Fri, 04 Jul 2026 00:00:00 +0000
```

- [ ] **Step 5: Create `debian/control`**

```
Source: asus-backlight-fix
Section: admin
Priority: optional
Maintainer: Baraka Malila <bmalila87@gmail.com>
Build-Depends: debhelper-compat (= 12)
Standards-Version: 4.6.2
Homepage: https://github.com/Baraka-Malila/asusctl-ubuntu

Package: asus-backlight-fix
Architecture: all
Depends: initramfs-tools, ${misc:Depends}
Description: Workaround for the FA507NV-family gsd-power backlight race
 On ASUS TUF laptops that expose both amdgpu_bl* (real panel) and nvidia_0
 (shadow via nvidia_wmi_ec_backlight), GNOME's power daemon races between
 the two interfaces and the brightness slider silently no-ops ~half the
 time. This package installs a modprobe blacklist for
 nvidia_wmi_ec_backlight and regenerates the initramfs so only amdgpu_bl*
 remains at boot on affected hardware.
 .
 On hardware that does not match the pattern, the postinst leaves the
 blacklist file as .disabled — safe on ROG / Intel-based / non-affected
 systems.
```

- [ ] **Step 6: Create `debian/compat`**

Single line: `12`.

- [ ] **Step 7: Create `debian/source/format`**

Single line: `3.0 (quilt)`.

- [ ] **Step 8: Create `debian/copyright`**

```
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: asus-backlight-fix
Source: https://github.com/Baraka-Malila/asusctl-ubuntu

Files: *
Copyright: 2026 Baraka Malila <bmalila87@gmail.com>
License: MPL-2.0

License: MPL-2.0
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this file,
 You can obtain one at https://mozilla.org/MPL/2.0/.
```

- [ ] **Step 9: Create `debian/rules`**

```
#!/usr/bin/make -f
%:
	dh $@
```

Make it executable: `chmod +x packages/asus-backlight-fix/debian/rules`.

- [ ] **Step 10: Create `debian/asus-backlight-fix.install`**

```
files/asusctl-fa507nv-backlight-fix.conf.disabled etc/modprobe.d/
```

- [ ] **Step 11: Create `debian/asus-backlight-fix.postinst`**

```sh
#!/bin/sh
set -e

case "$1" in
    configure)
        if lsmod | grep -q "^nvidia_wmi_ec_backlight" \
           && ls /sys/class/backlight/amdgpu_bl* >/dev/null 2>&1 \
           && ls /sys/class/backlight/nvidia_0    >/dev/null 2>&1 ; then
            if [ -f /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf.disabled ]; then
                mv /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf.disabled \
                   /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf
                update-initramfs -u
                echo "asus-backlight-fix: activated (FA507NV-family hardware detected). Reboot to apply."
            fi
        else
            echo "asus-backlight-fix: skipped — hardware does not match the FA507NV race pattern. Blacklist file left as .disabled; activate manually if needed."
        fi
        ;;
esac

#DEBHELPER#
```

Make executable: `chmod +x packages/asus-backlight-fix/debian/asus-backlight-fix.postinst`.

- [ ] **Step 12: Create `debian/asus-backlight-fix.postrm`**

```sh
#!/bin/sh
set -e

case "$1" in
    remove|purge)
        if [ -f /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf ]; then
            mv /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf \
               /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf.disabled
            update-initramfs -u
        fi
        ;;
esac

if [ "$1" = "purge" ]; then
    rm -f /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf.disabled
fi

#DEBHELPER#
```

Make executable.

- [ ] **Step 13: Build source + binary**

```bash
./scripts/build-source-package.sh asus-backlight-fix
./scripts/build-deb-pbuilder.sh asus-backlight-fix
ls packages/asus-backlight-fix/build/*.deb
```

Expected: `asus-backlight-fix_1.0-1~jammy1_all.deb` present.

- [ ] **Step 14: Lintian**

```bash
lintian packages/asus-backlight-fix/build/asus-backlight-fix_1.0-1~jammy1_all.deb
```

Warnings acceptable; errors block PR (fix them).

- [ ] **Step 15: Install + verify on FA507NV**

```bash
echo '381011' | sudo -S dpkg -i packages/asus-backlight-fix/build/asus-backlight-fix_1.0-1~jammy1_all.deb
echo '381011' | sudo -S apt install -f
```

Expected postinst output: since FA507NV **does** match the pattern, `asus-backlight-fix: activated (FA507NV-family hardware detected). Reboot to apply.`

Check that the file was renamed:

```bash
ls /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf 2>&1
ls /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf.disabled 2>&1
```

Expected: `.conf` exists; `.conf.disabled` does not.

- [ ] **Step 16: Purge and verify rollback**

```bash
echo '381011' | sudo -S apt-get purge -y asus-backlight-fix
ls /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf         2>&1  # absent
ls /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf.disabled 2>&1  # absent
```

Both should be absent (purge deleted the `.disabled` too).

- [ ] **Step 17: Verification report + PR**

Write `docs/superpowers/verification/2026-07-04-phase2b-verify-task2.md` with the postinst log line, file paths pre/post install, and purge state. Then:

```bash
git checkout -b phase2b/task2-asus-backlight-fix
git add packages/asus-backlight-fix docs/superpowers/verification/2026-07-04-phase2b-verify-task2.md
git commit -m "Phase 2b Task 2: asus-backlight-fix package"
git push -u origin phase2b/task2-asus-backlight-fix
gh pr create --title "Phase 2b Task 2: asus-backlight-fix.deb" \
    --body "Modprobe blacklist for the FA507NV-family gsd-power race. Hardware-gated postinst. Verified on FA507NV: activated on install, cleanly removed on purge."
```

---

### Task 3: `asusctl` package

**Files:**
- Create: `packages/asusctl/upstream.env`
- Create: `packages/asusctl/debian/changelog`
- Create: `packages/asusctl/debian/control`
- Create: `packages/asusctl/debian/copyright`
- Create: `packages/asusctl/debian/rules`
- Create: `packages/asusctl/debian/compat`
- Create: `packages/asusctl/debian/source/format`
- Create: `packages/asusctl/debian/asusctl.install`
- Create: `packages/asusctl/debian/asusctl.preinst`
- Create: `packages/asusctl/debian/asusctl.postinst`
- Create: `packages/asusctl/debian/asusctl.postrm`
- Create: `docs/superpowers/verification/2026-07-04-phase2b-verify-task3.md`

**Consumes:** Task 1 build tooling. `patches/asusctl/series` (three patches: 0001, 0002, 0003).

**Produces:** `packages/asusctl/build/asusctl_6.3.8-1~jammy1_amd64.deb`.

**Interfaces:**
- Consumes: `build-source-package.sh` (with upstream tarball fetch), `build-deb-pbuilder.sh`.
- Produces: package `asusctl` at version `6.3.8-1~jammy1`, consumed by Task 5 (`asusctl-suite.Depends`).

- [ ] **Step 1: Create `packages/asusctl/upstream.env`**

```bash
# asusctl 6.3.8 from OGC (Phase 2a fork base).
UPSTREAM_TAG=6.3.8
ORIG_NAME=asusctl
TARBALL_URL="https://github.com/OpenGamingCollective/asusctl/archive/refs/tags/6.3.8.tar.gz"
```

- [ ] **Step 2: Create `debian/changelog`**

```
asusctl (6.3.8-1~jammy1) jammy; urgency=medium

  * Phase 2b Task 3: initial Debian packaging for asusctl 6.3.8
    (Ubuntu-first fork).
  * Applies patches from patches/asusctl/series:
    - 0001-power-source-sysfs-watcher (systemd 249 workaround)
    - 0002-kbd-brightness-on-power    (opt-in kbd LED per power source)
    - 0003-gpu-mode-per-power         (opt-in GPU mode auto-switch via
                                       supergfxd dbus)

 -- Baraka Malila <bmalila87@gmail.com>  Fri, 04 Jul 2026 00:00:00 +0000
```

- [ ] **Step 3: Create `debian/control`**

```
Source: asusctl
Section: admin
Priority: optional
Maintainer: Baraka Malila <bmalila87@gmail.com>
Build-Depends: debhelper-compat (= 12),
               cargo (>= 0.66),
               rustc (>= 1.82),
               libudev-dev,
               libclang-dev,
               libinput-dev,
               pkg-config,
               quilt
Standards-Version: 4.6.2
Homepage: https://github.com/Baraka-Malila/asusctl-ubuntu

Package: asusctl
Architecture: amd64
Depends: ${shlibs:Depends}, ${misc:Depends}, systemd, dbus
Conflicts: rog-control-center
Description: Control fan speeds, LEDs, graphics modes, and charge levels for ASUS notebooks
 Ubuntu-first fork by Baraka Malila; upstream at OpenGamingCollective.
 Ships asusd (system daemon) + asusctl (CLI) + asus-shutdown (systemd
 helper). This package does not include the Slint-based rog-control-center
 GUI or the user-session asusd-user daemon.
```

- [ ] **Step 4: Create `debian/compat` and `debian/source/format`**

```bash
mkdir -p packages/asusctl/debian/source
echo 12 > packages/asusctl/debian/compat
printf '3.0 (quilt)\n' > packages/asusctl/debian/source/format
```

- [ ] **Step 5: Create `debian/copyright`**

Same shape as Task 2's, adjust Files clause to note upstream authorship:

```
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: asusctl
Source: https://github.com/OpenGamingCollective/asusctl

Files: *
Copyright: 2018-2026 Luke Jones <luke@ljones.dev>
           2026 Baraka Malila <bmalila87@gmail.com>
License: MPL-2.0

License: MPL-2.0
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this file,
 You can obtain one at https://mozilla.org/MPL/2.0/.
```

- [ ] **Step 6: Create `debian/rules`**

```
#!/usr/bin/make -f

# Skip binaries we don't ship in v0.1: asusd-user (session daemon) and
# rog-control-center (Slint GUI, rejected by design).

%:
	dh $@ --with quilt

override_dh_auto_build:
	cargo build --release --workspace \
	    --exclude asusd-user \
	    --exclude rog-control-center

override_dh_auto_test:
	# Upstream cargo tests reach hardware; skip in the pbuilder chroot.

override_dh_auto_install:
	# Handled via debian/asusctl.install (enumerated).
```

Make executable.

- [ ] **Step 7: Create `debian/asusctl.install` (enumerated per spec §7 discipline)**

```
target/release/asusd                usr/sbin/
target/release/asusctl              usr/bin/
target/release/asus-shutdown        usr/libexec/asusctl/
data/asusd.service                  lib/systemd/system/
data/asusd.conf                     usr/share/dbus-1/system.d/
data/asusd.rules                    lib/udev/rules.d/
data/asus-shutdown.service          lib/systemd/system/
data/icons                          usr/share/icons/
```

Note: `data/asusd-user.service` deliberately not installed (not shipping the user daemon). `data/supergfxd.preset` is in the supergfxctl tree, not asusctl.

- [ ] **Step 8: Create `debian/asusctl.preinst`**

```sh
#!/bin/sh
set -e

case "$1" in
    install|upgrade)
        if systemctl is-active --quiet battery-charge-threshold.service 2>/dev/null; then
            echo "asusctl: stopping existing battery-charge-threshold.service (asusd owns charge_control_end_threshold from now on)."
            systemctl stop battery-charge-threshold.service
            systemctl disable battery-charge-threshold.service || true
            mkdir -p /var/lib/asusctl
            touch /var/lib/asusctl/batsvc-was-active
        fi
        ;;
esac

#DEBHELPER#
```

Make executable.

- [ ] **Step 9: Create `debian/asusctl.postinst`**

Minimal — `dh_installsystemd` handles enable + start of `asusd.service`:

```sh
#!/bin/sh
set -e
#DEBHELPER#
```

Make executable.

- [ ] **Step 10: Create `debian/asusctl.postrm`**

```sh
#!/bin/sh
set -e

if [ "$1" = "purge" ]; then
    if [ -f /var/lib/asusctl/batsvc-was-active ]; then
        echo "asusctl: restoring battery-charge-threshold.service to enabled+active state."
        systemctl enable  battery-charge-threshold.service 2>/dev/null || true
        systemctl start   battery-charge-threshold.service 2>/dev/null || true
        rm -f /var/lib/asusctl/batsvc-was-active
    fi
    rm -rf /var/lib/asusctl /etc/asusd
fi

#DEBHELPER#
```

Make executable.

- [ ] **Step 11: Build source + binary**

```bash
./scripts/build-source-package.sh asusctl
./scripts/build-deb-pbuilder.sh asusctl
ls packages/asusctl/build/*.deb
```

Build takes 12-15 min (cargo compile in pbuilder chroot from scratch). Expected: `asusctl_6.3.8-1~jammy1_amd64.deb`.

- [ ] **Step 12: Lintian**

```bash
lintian packages/asusctl/build/asusctl_6.3.8-1~jammy1_amd64.deb 2>&1 | tee /tmp/lintian-asusctl.log | head -40
```

Errors block PR; warnings acceptable.

- [ ] **Step 13: Install on FA507NV**

```bash
echo '381011' | sudo -S dpkg -i packages/asusctl/build/asusctl_6.3.8-1~jammy1_amd64.deb
echo '381011' | sudo -S apt install -f
```

Expected preinst output: `asusctl: stopping existing battery-charge-threshold.service ...`.

- [ ] **Step 14: Verify service state**

```bash
systemctl is-active  asusd.service                        # active
systemctl is-enabled asusd.service                        # enabled
systemctl is-active  battery-charge-threshold.service     # inactive
systemctl is-enabled battery-charge-threshold.service     # disabled
ls -la /var/lib/asusctl/batsvc-was-active                 # exists
```

- [ ] **Step 15: Verify functionality**

```bash
asusctl profile set Balanced
cat /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy   # 0
asusctl leds set med
cat /sys/class/leds/asus::kbd_backlight/brightness              # 2
asusctl battery limit 80
cat /sys/class/power_supply/BAT1/charge_control_end_threshold   # 80
```

- [ ] **Step 16: Purge + verify rollback**

```bash
echo '381011' | sudo -S apt-get purge -y asusctl
systemctl is-active  asusd.service                        # inactive
systemctl is-active  battery-charge-threshold.service     # active
systemctl is-enabled battery-charge-threshold.service     # enabled
ls -la /var/lib/asusctl/ 2>&1                             # absent
ls -la /etc/asusd/     2>&1                                # absent
```

- [ ] **Step 17: Verification report + PR**

Write `docs/superpowers/verification/2026-07-04-phase2b-verify-task3.md` with the pre/post install state + functional test output + purge state. Then:

```bash
git checkout -b phase2b/task3-asusctl-deb
git add packages/asusctl docs/superpowers/verification/2026-07-04-phase2b-verify-task3.md
git commit -m "Phase 2b Task 3: asusctl.deb"
git push -u origin phase2b/task3-asusctl-deb
gh pr create --title "Phase 2b Task 3: asusctl.deb" \
    --body "Debian package for our forked asusctl 6.3.8 with the three Phase 2a patches applied. preinst stops+disables battery-charge-threshold.service; postrm restores. Verified on FA507NV: install, functional tests, purge round-trip."
```

---

### Task 4: `supergfxctl` package

**Files:**
- Create: `packages/supergfxctl/upstream.env`
- Create: `packages/supergfxctl/debian/changelog`
- Create: `packages/supergfxctl/debian/control`
- Create: `packages/supergfxctl/debian/copyright`
- Create: `packages/supergfxctl/debian/rules`
- Create: `packages/supergfxctl/debian/compat`
- Create: `packages/supergfxctl/debian/source/format`
- Create: `packages/supergfxctl/debian/supergfxctl.install`
- Create: `packages/supergfxctl/debian/supergfxctl.postinst`
- Create: `docs/superpowers/verification/2026-07-04-phase2b-verify-task4.md`

**Consumes:** Task 1 build tooling. `patches/supergfxctl/series` (one patch: 0001-drop-99-nvidia-ac-rules).

**Produces:** `packages/supergfxctl/build/supergfxctl_5.2.7-1~jammy1_amd64.deb`.

**Interfaces:**
- Consumes: `build-source-package.sh` (upstream tarball from GitLab), `build-deb-pbuilder.sh`.
- Produces: package `supergfxctl` at version `5.2.7-1~jammy1`, consumed by Task 5.

- [ ] **Step 1: Create `packages/supergfxctl/upstream.env`**

```bash
UPSTREAM_TAG=5.2.7
ORIG_NAME=supergfxctl
TARBALL_URL="https://gitlab.com/asus-linux/supergfxctl/-/archive/5.2.7/supergfxctl-5.2.7.tar.gz"
```

- [ ] **Step 2: Create `debian/changelog`**

```
supergfxctl (5.2.7-1~jammy1) jammy; urgency=medium

  * Phase 2b Task 4: initial Debian packaging for supergfxctl 5.2.7
    (Ubuntu-first fork).
  * Applies patches from patches/supergfxctl/series:
    - 0001-drop-99-nvidia-ac-rules   (crash trigger removed from tree)

 -- Baraka Malila <bmalila87@gmail.com>  Fri, 04 Jul 2026 00:00:00 +0000
```

- [ ] **Step 3: Create `debian/control`**

```
Source: supergfxctl
Section: admin
Priority: optional
Maintainer: Baraka Malila <bmalila87@gmail.com>
Build-Depends: debhelper-compat (= 12),
               cargo (>= 0.66),
               rustc (>= 1.82),
               pkg-config,
               quilt
Standards-Version: 4.6.2
Homepage: https://github.com/Baraka-Malila/asusctl-ubuntu

Package: supergfxctl
Architecture: amd64
Depends: ${shlibs:Depends}, ${misc:Depends}, systemd, dbus
Description: Manage integrated / hybrid / dedicated GPU modes on ASUS laptops
 Ubuntu-first fork by Baraka Malila; upstream at asus-linux (GitLab).
 Ships supergfxd (system daemon) + supergfxctl (CLI) + a safe udev rule
 subset (deliberately excludes the AC-transition rule that crashes NVIDIA
 driver on some TUF/ROG hardware; see the Phase 1 verification report
 for details).
```

- [ ] **Step 4: Create `debian/compat` and `debian/source/format`**

```bash
mkdir -p packages/supergfxctl/debian/source
echo 12 > packages/supergfxctl/debian/compat
printf '3.0 (quilt)\n' > packages/supergfxctl/debian/source/format
```

- [ ] **Step 5: Create `debian/copyright`**

```
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: supergfxctl
Source: https://gitlab.com/asus-linux/supergfxctl

Files: *
Copyright: 2020-2026 Luke Jones <luke@ljones.dev>
           2026 Baraka Malila <bmalila87@gmail.com>
License: MPL-2.0

License: MPL-2.0
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this file,
 You can obtain one at https://mozilla.org/MPL/2.0/.
```

- [ ] **Step 6: Create `debian/rules`**

```
#!/usr/bin/make -f
%:
	dh $@ --with quilt

override_dh_auto_build:
	cargo build --release --features "daemon cli"

override_dh_auto_test:
	# Upstream cargo tests reach hardware; skip in the pbuilder chroot.

override_dh_auto_install:
	# Handled via debian/supergfxctl.install (enumerated).
```

Make executable.

- [ ] **Step 7: Create `debian/supergfxctl.install` (enumerated — do NOT `data/*.rules`, per spec §7 discipline; defensive against patch 0001 regression)**

```
target/release/supergfxd            usr/sbin/
target/release/supergfxctl          usr/bin/
data/supergfxd.service              lib/systemd/system/
data/supergfxd.preset               lib/systemd/system-preset/
data/org.supergfxctl.Daemon.conf    usr/share/dbus-1/system.d/
data/90-supergfxd-nvidia-pm.rules   lib/udev/rules.d/
data/90-nvidia-screen-G05.conf      usr/share/X11/xorg.conf.d/
```

Note the enumeration **excludes** `data/99-nvidia-ac.rules` — the patch drops it from the tree, but the enumeration protects future rebases where the patch might get lost.

- [ ] **Step 8: Create `debian/supergfxctl.postinst`**

```sh
#!/bin/sh
set -e

case "$1" in
    configure)
        # Warn if nvidia-prime is co-installed. Not fatal — spec §7.2 is
        # explicit: we do not disable either package.
        if dpkg -l nvidia-prime 2>/dev/null | grep -q "^ii"; then
            echo "supergfxctl: nvidia-prime is installed. supergfxctl and" >&2
            echo "  nvidia-prime can coexist but may confuse each other on GPU" >&2
            echo "  mode switches. If you use supergfxctl to switch modes, prefer" >&2
            echo "  it over nvidia-prime and consider removing nvidia-prime." >&2
        fi
        ;;
esac

#DEBHELPER#
```

Make executable.

- [ ] **Step 9: Build source + binary**

```bash
./scripts/build-source-package.sh supergfxctl
./scripts/build-deb-pbuilder.sh supergfxctl
ls packages/supergfxctl/build/*.deb
```

Build takes ~3 min (supergfxctl is much smaller than asusctl). Expected: `supergfxctl_5.2.7-1~jammy1_amd64.deb`.

- [ ] **Step 10: Lintian**

```bash
lintian packages/supergfxctl/build/supergfxctl_5.2.7-1~jammy1_amd64.deb
```

- [ ] **Step 11: Install on FA507NV**

```bash
echo '381011' | sudo -S dpkg -i packages/supergfxctl/build/supergfxctl_5.2.7-1~jammy1_amd64.deb
echo '381011' | sudo -S apt install -f
systemctl is-active supergfxd.service    # active
supergfxctl -g                            # Hybrid
```

- [ ] **Step 12: Verify no 99-nvidia-ac.rules on disk**

```bash
ls /lib/udev/rules.d/ | grep nvidia-ac 2>&1 && echo "FAIL: crash rule installed" || echo "PASS: not installed"
```

Expected: PASS.

- [ ] **Step 13: Purge + verify**

```bash
echo '381011' | sudo -S apt-get purge -y supergfxctl
systemctl is-active supergfxd.service        # inactive
which supergfxctl                             # not found
ls /lib/udev/rules.d/90-supergfxd-nvidia-pm.rules 2>&1   # absent
```

- [ ] **Step 14: Verification report + PR**

Write `docs/superpowers/verification/2026-07-04-phase2b-verify-task4.md` with install + functional test + purge state. Then:

```bash
git checkout -b phase2b/task4-supergfxctl-deb
git add packages/supergfxctl docs/superpowers/verification/2026-07-04-phase2b-verify-task4.md
git commit -m "Phase 2b Task 4: supergfxctl.deb"
git push -u origin phase2b/task4-supergfxctl-deb
gh pr create --title "Phase 2b Task 4: supergfxctl.deb" \
    --body "Debian package for our forked supergfxctl 5.2.7 with patch 0001 (drop 99-nvidia-ac.rules). Enumerated debian/install prevents accidental re-inclusion on future rebases. Verified on FA507NV: install, mode read, purge round-trip."
```

---

### Task 5: `asusctl-suite` meta-package

**Files:**
- Create: `packages/asusctl-suite/upstream.env`
- Create: `packages/asusctl-suite/debian/changelog`
- Create: `packages/asusctl-suite/debian/control`
- Create: `packages/asusctl-suite/debian/copyright`
- Create: `packages/asusctl-suite/debian/rules`
- Create: `packages/asusctl-suite/debian/compat`
- Create: `packages/asusctl-suite/debian/source/format`
- Create: `docs/superpowers/verification/2026-07-04-phase2b-verify-task5.md`

**Consumes:** Tasks 2, 3, 4 outputs (need the `.deb` versions for `Depends:` and `Recommends:` lines).

**Produces:** `packages/asusctl-suite/build/asusctl-suite_1.0-1~jammy1_all.deb`.

**Interfaces:**
- Consumes: `build-source-package.sh` (with `NO_UPSTREAM=1`), `build-deb-pbuilder.sh`.
- Produces: nothing consumed by later tasks; Task 6 does the end-to-end verify.

- [ ] **Step 1: Create `packages/asusctl-suite/upstream.env`**

```bash
NO_UPSTREAM=1
```

- [ ] **Step 2: Create `debian/changelog`**

```
asusctl-suite (1.0-1~jammy1) jammy; urgency=medium

  * Phase 2b Task 5: initial meta-package. Pulls asusctl + supergfxctl;
    recommends asus-backlight-fix (activated on FA507NV-family hardware).

 -- Baraka Malila <bmalila87@gmail.com>  Fri, 04 Jul 2026 00:00:00 +0000
```

- [ ] **Step 3: Create `debian/control`**

```
Source: asusctl-suite
Section: metapackages
Priority: optional
Maintainer: Baraka Malila <bmalila87@gmail.com>
Build-Depends: debhelper-compat (= 12)
Standards-Version: 4.6.2
Homepage: https://github.com/Baraka-Malila/asusctl-ubuntu

Package: asusctl-suite
Architecture: all
Depends: asusctl (>= 6.3.8-1~jammy1),
         supergfxctl (>= 5.2.7-1~jammy1),
         ${misc:Depends}
Recommends: asus-backlight-fix
Description: Full ASUS Linux control stack for Ubuntu (meta-package)
 Installs asusd (system daemon), asusctl (CLI), supergfxd (GPU mode
 daemon), and supergfxctl (GPU mode CLI). Recommends the FA507NV-family
 backlight fix. This is what most users want:
 .
   sudo apt install asusctl-suite
```

- [ ] **Step 4: Create `debian/compat`, `debian/source/format`, `debian/copyright`**

```bash
mkdir -p packages/asusctl-suite/debian/source
echo 12 > packages/asusctl-suite/debian/compat
printf '3.0 (quilt)\n' > packages/asusctl-suite/debian/source/format
```

Copy the copyright shape from Task 2 (own-work MPL-2.0, no upstream author line).

- [ ] **Step 5: Create `debian/rules`**

```
#!/usr/bin/make -f
%:
	dh $@
```

Make executable.

- [ ] **Step 6: Build source + binary**

```bash
./scripts/build-source-package.sh asusctl-suite
./scripts/build-deb-pbuilder.sh asusctl-suite
ls packages/asusctl-suite/build/*.deb
```

Expected: `asusctl-suite_1.0-1~jammy1_all.deb`.

- [ ] **Step 7: Lintian**

```bash
lintian packages/asusctl-suite/build/asusctl-suite_1.0-1~jammy1_all.deb
```

- [ ] **Step 8: Ensure the three dep packages are installed first (from Tasks 2-4)**

```bash
dpkg -l | grep -E "^ii  (asusctl|supergfxctl|asus-backlight-fix)"
```

If Task 4's supergfxctl was purged for Task 4 Step 13, reinstall now:

```bash
echo '381011' | sudo -S dpkg -i packages/asus-backlight-fix/build/*.deb packages/asusctl/build/*.deb packages/supergfxctl/build/*.deb
echo '381011' | sudo -S apt install -f
```

- [ ] **Step 9: Install the meta-package**

```bash
echo '381011' | sudo -S dpkg -i packages/asusctl-suite/build/asusctl-suite_1.0-1~jammy1_all.deb
echo '381011' | sudo -S apt install -f
dpkg -l asusctl-suite asusctl supergfxctl asus-backlight-fix | grep "^ii"
```

Expected: all four rows `^ii`.

- [ ] **Step 10: Verify Recommends resolved**

```bash
apt-cache depends asusctl-suite
```

Expected: shows `Depends: asusctl`, `Depends: supergfxctl`, `Recommends: asus-backlight-fix`.

- [ ] **Step 11: Verification report + PR**

Write `docs/superpowers/verification/2026-07-04-phase2b-verify-task5.md` with the install state + `apt-cache depends` output. Then:

```bash
git checkout -b phase2b/task5-asusctl-suite
git add packages/asusctl-suite docs/superpowers/verification/2026-07-04-phase2b-verify-task5.md
git commit -m "Phase 2b Task 5: asusctl-suite meta-package"
git push -u origin phase2b/task5-asusctl-suite
gh pr create --title "Phase 2b Task 5: asusctl-suite.deb (meta)" \
    --body "Meta-package. Depends asusctl + supergfxctl; Recommends asus-backlight-fix. Verified on FA507NV: install pulls all deps + recommends; apt-cache depends confirms structure."
```

---

### Task 6: End-to-end install + purge + Phase 2b exit report

**Files:**
- Create: `docs/superpowers/verification/2026-07-04-phase2b-exit.md`
- Modify: `docs/superpowers/verification/2026-07-04-phase2b-verify-task6.md` — the end-to-end test log

**Consumes:** All four `.deb` files from Tasks 2-5.

**Produces:** Full round-trip verification + Phase 2b exit report + tag instructions.

**Interfaces:** none; terminal task.

- [ ] **Step 1: Full clean slate on FA507NV**

```bash
echo '381011' | sudo -S bash scripts/phase2b-teardown-debs.sh
```

Verify:

```bash
dpkg -l | grep -E "asusctl|supergfxctl|asus-backlight-fix" && echo "FAIL" || echo "PASS: clean"
```

- [ ] **Step 2: Fresh install via the meta-package + local `.deb` files (simulates apt)**

```bash
echo '381011' | sudo -S dpkg -i \
    packages/asus-backlight-fix/build/*.deb \
    packages/asusctl/build/*.deb \
    packages/supergfxctl/build/*.deb \
    packages/asusctl-suite/build/*.deb
echo '381011' | sudo -S apt install -f
```

- [ ] **Step 3: Confirm daemons + preinst migrations**

```bash
systemctl is-active  asusd.service                        # active
systemctl is-active  supergfxd.service                    # active
systemctl is-active  battery-charge-threshold.service     # inactive
systemctl is-enabled battery-charge-threshold.service     # disabled
ls /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf     # present (not .disabled)
```

- [ ] **Step 4: Functional sanity check**

```bash
asusctl profile set Balanced
asusctl leds set med
asusctl battery limit 80
supergfxctl -g                       # Hybrid
```

All must succeed with matching sysfs state.

- [ ] **Step 5: Purge round-trip**

```bash
echo '381011' | sudo -S bash scripts/phase2b-teardown-debs.sh
```

Confirm:

```bash
systemctl is-active  battery-charge-threshold.service     # active
systemctl is-enabled battery-charge-threshold.service     # enabled
which asusctl 2>&1 && echo "FAIL" || echo "PASS: absent"
which supergfxctl 2>&1 && echo "FAIL" || echo "PASS: absent"
ls /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf         2>&1   # absent
ls /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf.disabled 2>&1  # absent (purge deleted)
ls /var/lib/asusctl/ 2>&1                                             # absent
ls /etc/asusd/       2>&1                                             # absent
```

- [ ] **Step 6: Diff against pre-flight snapshot**

```bash
SNAP=/var/lib/asus-phase1-fork/phase2b
diff <(cat /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy)  "$SNAP/thermal"  && echo "thermal ✓"
diff <(cat /sys/class/power_supply/BAT1/charge_control_end_threshold)  "$SNAP/charge"   && echo "charge ✓"
diff <(cat /sys/devices/platform/asus-nb-wmi/gpu_mux_mode)             "$SNAP/gpu_mux"  && echo "gpu_mux ✓"
diff <(cat /proc/cmdline)                                              "$SNAP/cmdline"  && echo "cmdline ✓"
diff /etc/modprobe.d/nvidia-custom.conf                                "$SNAP/nvidia-custom.conf" && echo "nvidia-custom ✓"
```

Every check must PASS. Any drift is a Phase 2b bug — must be fixed in whichever package's post-scripts caused it before the exit report is landed.

- [ ] **Step 7: Write exit report `docs/superpowers/verification/2026-07-04-phase2b-exit.md`**

Structure:

- Phase 2b verdict (GO for Phase 2b.5 / Phase 2c, or blocker)
- The four .deb files delivered (with sizes + build times)
- Deferrals honored (Phase 2b.5 = DKMS, Phase 2c = PPA/CI/docs)
- Pre-flight vs post-purge diff table (all match)
- Known follow-ups from implementation-time discoveries

- [ ] **Step 8: Feature branch + PR**

```bash
git checkout -b phase2b/task6-exit-report
git add docs/superpowers/verification/2026-07-04-phase2b-exit.md \
        docs/superpowers/verification/2026-07-04-phase2b-verify-task6.md
git commit -m "Phase 2b Task 6: end-to-end verification + exit report"
git push -u origin phase2b/task6-exit-report
gh pr create --title "Phase 2b Task 6: end-to-end verification + exit" \
    --body "Full round-trip: install all four .debs on FA507NV → daemons active + preinst migration correct → functional sanity → purge → back to pre-flight snapshot. GO for Phase 2b.5 (asus-armoury-dkms) or Phase 2c (PPA + CI + docs)."
```

- [ ] **Step 9: After all Phase 2b PRs merge, tag** (user-only step)

```bash
git checkout main && git pull
git tag -a phase2b-v0.1-packaging \
    -m "Phase 2b: core Debian packaging (asusctl, supergfxctl, asus-backlight-fix, asusctl-suite). Verified on FA507NV Jammy."
git push origin phase2b-v0.1-packaging
```

---

## Phase 2b completion criteria

- All 6 task PRs merged by user.
- Four `.deb` files build cleanly via `./scripts/build-all-debs.sh` from a fresh clone.
- End-to-end install + functional test + purge round-trip clean on FA507NV.
- Pre-flight vs post-purge state diff is byte-identical.
- Exit report has explicit "GO for Phase 2b.5 / Phase 2c" verdict.
- Tag `phase2b-v0.1-packaging` on `main`.

Once tagged, Phase 2b.5 (`asus-armoury-dkms`) plan is written and executed. After 2b.5 lands, Phase 2c (Launchpad PPA + GitHub Actions CI matrix on Jammy + Noble + `install.md` + `troubleshoot.md` + first PPA upload) is written and executed. Together those two phases close v0.1.
