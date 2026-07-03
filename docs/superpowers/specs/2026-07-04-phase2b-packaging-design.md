# Phase 2b — Debian packaging design (core packages only)

**Date:** 2026-07-04
**Depends on:** Phase 2a (`phase2a-v0.1-patches` tag). The `patches/asusctl/series` and `patches/supergfxctl/series` are the source of truth this phase consumes.
**Blocks:** Phase 2b.5 (`asus-armoury-dkms`) — same repo, similar tooling, but its own package. Phase 2c (PPA + CI + docs + first release) — depends on Phase 2b's `.deb` output.
**Test hardware:** ASUS TUF Gaming A15 FA507NV, Ubuntu 22.04 Jammy.

## 1. Purpose

Produce four Debian source packages, each buildable locally on Jammy via `pbuilder`, that reproduce our fork's daemon + CLI on FA507NV. User entry point: `sudo apt install asusctl-suite`.

Deliberately excludes DKMS (Phase 2b.5), Launchpad PPA (Phase 2c), CI (Phase 2c), user docs (Phase 2c), Noble local verification (Phase 2c CI), AppArmor profile (v0.2), `asusd-user`, `rog-control-center`.

## 2. Package inventory

| Package | Kind | Ships | Depends inbound |
|---|---|---|---|
| `asusctl` | Source: `asusctl`. Binary: `asusctl`. | `asusd` + `asusctl` + `asus-shutdown` binaries, systemd unit, dbus policy, udev rule, config templates, service migration hooks. | none inbound |
| `supergfxctl` | Source: `supergfxctl`. Binary: `supergfxctl`. | `supergfxd` + `supergfxctl` binaries, systemd unit, dbus policy, `90-supergfxd-nvidia-pm.rules`, `90-nvidia-screen-G05.conf`, `supergfxd.conf` with `DisplayManager=gdm3`. | none inbound |
| `asus-backlight-fix` | Source: `asus-backlight-fix`. Binary: `asus-backlight-fix`. | Modprobe blacklist file + hardware-gated postinst that runs `update-initramfs -u`. | none inbound |
| `asusctl-suite` | Source + Binary: `asusctl-suite`. Meta. | Nothing. `Depends: asusctl, supergfxctl` + `Recommends: asus-backlight-fix`. | pulls the above |

## 3. Repo layout

```
packages/
├── asusctl/debian/
├── supergfxctl/debian/
├── asus-backlight-fix/
│   ├── debian/
│   └── files/
│       └── asusctl-fa507nv-backlight-fix.conf   # shipped as .disabled at install
└── asusctl-suite/debian/

scripts/
├── build-source-package.sh   # fetch upstream tarball, apply patches/*/series -> generate 3.0 (quilt) source
├── build-deb-pbuilder.sh     # per-package: pbuilder-based binary build inside Jammy chroot
└── build-all-debs.sh         # convenience: source + binary for all 4 packages

pbuilderrc                    # pbuilder config (Jammy target, deb-src mirrors, hook dir)
```

Existing `patches/asusctl/series` and `patches/supergfxctl/series` are copied verbatim into the source package's `debian/patches/series` at build time. Our fork's `patches/` remains the single source of truth; the debian tree does not duplicate patch content.

## 4. Build tooling

- **`3.0 (quilt)` source format** — upstream `.orig.tar.xz` fetched from the tag (GitHub for asusctl, GitLab for supergfxctl), quilt patches applied at build.
- **`pbuilder`** for reproducible chroot builds. Configured to target Jammy `deb-src` repos; base tarball cached at `/var/cache/pbuilder/base-jammy.tgz`.
- **`debhelper compat 12`** — Jammy default, stable for our tooling.
- **`quilt`** patch tooling — matches `patches/*/series` semantics 1:1.

## 5. Version scheme

`<upstream>-<pkg-rev>~<distro><distro-rev>`.

- `asusctl`: `6.3.8-1~jammy1`
- `supergfxctl`: `5.2.7-1~jammy1`
- `asus-backlight-fix`: `1.0-1~jammy1` (our own versioning; no upstream)
- `asusctl-suite`: `1.0-1~jammy1`

The `~jammy1` suffix ensures Ubuntu version-comparison prefers our Jammy build over any hypothetical newer Debian upload of the same upstream.

## 6. `asusctl.deb`

### control

```
Source: asusctl
Section: admin
Priority: optional
Maintainer: Baraka Malila <bmalila87@gmail.com>
Build-Depends: debhelper-compat (= 12),
               cargo (>= 0.66),
               rustc (>= 1.82),
               libudev-dev, libclang-dev, libinput-dev, pkg-config,
               quilt
Standards-Version: 4.6.2
Homepage: https://github.com/Baraka-Malila/asusctl-ubuntu

Package: asusctl
Architecture: amd64
Depends: ${shlibs:Depends}, ${misc:Depends}, systemd, dbus
Conflicts: rog-control-center
Description: Control fan speeds, LEDs, graphics modes, and charge levels for ASUS notebooks
 Ubuntu-first fork by Baraka Malila; upstream at OpenGamingCollective.
 Ships asusd (system daemon) + asusctl (CLI) + asus-shutdown (systemd helper).
```

### rules

`dh $@ --with-quilt`. `override_dh_auto_build`: `cargo build --release --workspace --exclude asusd-user --exclude rog-control-center`.

### install (enumerated, never globbed)

```
target/release/asusd          usr/sbin/
target/release/asusctl        usr/bin/
target/release/asus-shutdown  usr/libexec/asusctl/
data/asusd.service            lib/systemd/system/
data/asusd.conf               usr/share/dbus-1/system.d/
data/asusd.rules              lib/udev/rules.d/
data/asus-shutdown.service    lib/systemd/system/
data/icons/                   usr/share/icons/
```

### preinst

```sh
#!/bin/sh
set -e
if [ "$1" = "install" ] || [ "$1" = "upgrade" ]; then
    if systemctl is-active --quiet battery-charge-threshold.service 2>/dev/null; then
        echo "asusctl: stopping existing battery-charge-threshold.service; asusd will own the sysfs from now on."
        systemctl stop battery-charge-threshold.service
        systemctl disable battery-charge-threshold.service || true
        mkdir -p /var/lib/asusctl
        touch /var/lib/asusctl/batsvc-was-active
    fi
fi
#DEBHELPER#
```

### postinst

`dh_installsystemd` handles `enable + start asusd.service` via `#DEBHELPER#` — no custom postinst body needed beyond the marker.

### postrm

```sh
#!/bin/sh
set -e
if [ "$1" = "purge" ]; then
    if [ -f /var/lib/asusctl/batsvc-was-active ]; then
        systemctl enable  battery-charge-threshold.service 2>/dev/null || true
        systemctl start   battery-charge-threshold.service 2>/dev/null || true
        rm -f /var/lib/asusctl/batsvc-was-active
    fi
    rm -rf /var/lib/asusctl /etc/asusd
fi
#DEBHELPER#
```

### patches

`debian/patches/series` is generated at source-package build time from `../../patches/asusctl/series`:

```
0001-power-source-sysfs-watcher.patch
0002-kbd-brightness-on-power.patch
0003-gpu-mode-per-power.patch
```

## 7. `supergfxctl.deb`

Same shape as `asusctl.deb`. Deltas:

- Upstream tarball: `https://gitlab.com/asus-linux/supergfxctl/-/archive/5.2.7/supergfxctl-5.2.7.tar.gz`.
- `debian/patches/series` (from `patches/supergfxctl/series`): `0001-drop-99-nvidia-ac-rules.patch`.
- `debian/supergfxctl.install` enumerates every file under `data/` **except** `99-nvidia-ac.rules` (already removed by patch 0001, but enumeration is defensive per §7 discipline of `2026-07-02-nvidia-ac-rule-decision.md`):
  ```
  target/release/supergfxd     usr/sbin/
  target/release/supergfxctl   usr/bin/
  data/supergfxd.service       lib/systemd/system/
  data/supergfxd.preset        lib/systemd/system-preset/
  data/org.supergfxctl.Daemon.conf  usr/share/dbus-1/system.d/
  data/90-supergfxd-nvidia-pm.rules lib/udev/rules.d/
  data/90-nvidia-screen-G05.conf    usr/share/X11/xorg.conf.d/
  ```
- `supergfxctl.postinst` detects `nvidia-prime` presence and echoes a non-fatal warning if both are active (spec §7.2). Does not disable either.

## 8. `asus-backlight-fix.deb`

### control

```
Source: asus-backlight-fix
Section: admin
Priority: optional
Maintainer: Baraka Malila <bmalila87@gmail.com>
Build-Depends: debhelper-compat (= 12)
Standards-Version: 4.6.2

Package: asus-backlight-fix
Architecture: all
Depends: initramfs-tools
Description: Workaround for the FA507NV-family gsd-power backlight race
 On ASUS TUF laptops that expose both amdgpu_bl* (real panel) and nvidia_0
 (shadow via nvidia_wmi_ec_backlight), GNOME's power daemon races between
 the two interfaces and the brightness slider silently no-ops ~half the
 time. This package installs a modprobe blacklist for
 nvidia_wmi_ec_backlight and regenerates the initramfs so only amdgpu_bl*
 remains at boot on affected hardware.
```

### install

```
files/asusctl-fa507nv-backlight-fix.conf  etc/modprobe.d/
```

Suffix `.disabled` handling: the file is shipped as `asusctl-fa507nv-backlight-fix.conf.disabled` (rename by `dh_install` via a `debian/asus-backlight-fix.install` that maps source → dest with the `.disabled` suffix preserved).

### postinst

```sh
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    if lsmod | grep -q "^nvidia_wmi_ec_backlight" \
       && ls /sys/class/backlight/amdgpu_bl* >/dev/null 2>&1 \
       && ls /sys/class/backlight/nvidia_0    >/dev/null 2>&1 ; then
        if [ -f /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf.disabled ]; then
            mv /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf.disabled \
               /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf
            update-initramfs -u
            echo "asus-backlight-fix: activated (FA507NV-family hardware). Reboot to apply."
        fi
    else
        echo "asus-backlight-fix: skipped — hardware does not match the FA507NV race pattern. Blacklist file left as .disabled; you can activate it manually if needed."
    fi
fi
#DEBHELPER#
```

### postrm

```sh
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    if [ -f /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf ]; then
        mv /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf \
           /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf.disabled
        update-initramfs -u
    fi
fi
if [ "$1" = "purge" ]; then
    rm -f /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf.disabled
fi
#DEBHELPER#
```

## 9. `asusctl-suite.deb` (meta)

### control

```
Source: asusctl-suite
Section: metapackages
Priority: optional
Maintainer: Baraka Malila <bmalila87@gmail.com>
Build-Depends: debhelper-compat (= 12)
Standards-Version: 4.6.2

Package: asusctl-suite
Architecture: all
Depends: asusctl (>= 6.3.8-1~jammy1),
         supergfxctl (>= 5.2.7-1~jammy1)
Recommends: asus-backlight-fix
Description: Full ASUS Linux control stack for Ubuntu (meta-package)
 Installs asusd (system daemon), asusctl (CLI), supergfxd (GPU mode
 daemon), and supergfxctl (GPU mode CLI). Recommends the FA507NV-family
 backlight fix. This is what most users want — sudo apt install asusctl-suite.
```

### rules

Bare `dh $@`. No `.install`, no scripts.

## 10. Verification model (per task + end-to-end)

Each package task ends with a small on-hardware verification:

- Source build produces `<pkg>_<version>.dsc` + `.orig.tar.xz` + `.debian.tar.xz`.
- Binary build in pbuilder-Jammy produces `<pkg>_<version>_amd64.deb` (or `_all.deb` for arch-independent).
- `dpkg-deb --info` + `dpkg-deb --contents` reviewed — no unexpected files, all paths match `.install`.
- `lintian <pkg>_<version>_amd64.deb` — warnings acceptable, errors block PR.

**End-to-end verification (final task):**

1. Install all four `.deb` files: `sudo dpkg -i packages/*/build/*.deb; sudo apt install -f`.
2. Confirm services: `systemctl is-active asusd supergfxd`. Both `active`.
3. Confirm migration: `systemctl is-active battery-charge-threshold.service` = `inactive` (and `is-enabled` = `disabled`).
4. Confirm backlight: `/etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf` (not `.disabled`) present.
5. Confirm functionality: `asusctl profile set Balanced` + `supergfxctl -g` return expected results.
6. Purge cycle: `sudo apt purge asusctl-suite asusctl supergfxctl asus-backlight-fix`.
7. Post-purge state: all daemons stopped, files removed, `battery-charge-threshold.service` re-enabled + active, blacklist `.disabled` again, initramfs regenerated.
8. Diff against `/var/lib/asus-phase2b-snapshot/` (persistent, not tmpfs). Every drift is a bug.

Full log per stage lands in `docs/superpowers/verification/2026-07-04-phase2b-verify-taskN.md`.

## 11. Task order

1. **Build tooling** — `scripts/build-source-package.sh`, `scripts/build-deb-pbuilder.sh`, `scripts/build-all-debs.sh`, `pbuilderrc`, `.gitignore` updates for `packages/*/build/`, `packages/*/*.orig.tar.xz`.
2. **`asus-backlight-fix.deb`** — smallest, simplest package. Good practice for the tooling.
3. **`asusctl.deb`** — the big one. Uses `patches/asusctl/series` (3 patches).
4. **`supergfxctl.deb`** — parallel structure to asusctl.
5. **`asusctl-suite.deb`** — pure metadata.
6. **End-to-end install + purge verification** on FA507NV. Exit report + tag `phase2b-v0.1-packaging`.

## 12. Discipline (unchanged from Phase 1 / 2a)

- Feature branch per task: `phase2b/task-N-<slug>`
- PR at end, user merges (never `gh pr merge`)
- Verification on FA507NV real hardware
- Reference this spec in every PR body
- Session teardown restores pre-phase snapshot after each verification
- 300-line limit on shell/systemd/config files; debian/control and debian/rules may exceed

## 13. Rejected alternatives

- **Split daemon vs CLI per project (Approach B).** YAGNI for a desktop tool. Servers don't need asusctl.
- **Monolithic `asus-linux.deb` (Approach C).** Loses independent purge of asusd vs supergfxctl.
- **Backlight fix in asusd's postinst (Section 2 Option B).** Couples an unrelated hardware fix to daemon lifecycle; `update-initramfs -u` runs even on unaffected hardware.
- **Backlight fix in meta's postinst (Section 2 Option C).** Anti-idiomatic; Debian meta-packages should be Depends-only.
- **Dual dbus name via a Rust patch.** Every future rebase needs re-test; the affected user population is tiny (people with hand-written `dbus-send` scripts). Accept the rename; `troubleshoot.md` (Phase 2c) documents the one-string fix.
- **AppArmor profile in v0.1.** Deferred to v0.2 hardening per spec §7.1.
- **Native (3.0 native) source format.** Loses the quilt patch model that maps our `patches/*/series` cleanly.

## 14. Open decisions (implementation-time)

- Exact `debhelper` incantation for the `.disabled` suffix on the backlight file — some Debian mirrors auto-strip. Falls out during Task 2 verification.
- Whether `supergfxctl.postinst`'s `nvidia-prime` detection should emit stderr or `debconf` — recommend stderr (unblocks unattended installs).
- Version bump policy when we advance `patches/asusctl/series` mid-cycle without changing upstream tag: probably `6.3.8-2~jammy1`, etc. Codify in Phase 2c's release doc.

None are scope-changing.
