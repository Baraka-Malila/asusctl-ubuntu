# asusctl-ubuntu — Design Spec

**Date:** 2026-07-01
**Author:** Baraka Malila (with Claude Code brainstorming)
**Status:** v1 — Partially superseded after Phase 0 verification and reframe
**Scope:** Full project vision (Phase 0 through v0.3). Implementation plans are written per-phase.

---

> ### ⚠️ Reframe notice (2026-07-01, post-Phase 0)
>
> After Phase 0 verification revealed material bugs in upstream OGC asusctl v1.0.1 on FA507NV, and after a direct correction from Baraka on 2026-07-01, this project's framing shifted from "downstream packaging layer" to **independent Ubuntu-first fork with Armoury Crate feature parity as a hard goal**.
>
> The following sections of this v1 spec are **outdated** and superseded by the reframed recommendations doc:
>
> - **Section 2 non-goals** — spoke of deferring broken features to v0.2/v0.3. No feature is deferred; broken upstream features get patched in our tree for v0.1.
> - **Section 4 Approach** — described "Pure downstream packaging layer" and "we do not fork the upstream Rust codebase." Wrong. We fork, we patch, we own the shipped binary.
> - **Section 11 Upstream relationship** — described "additive and non-forking" and "contribute pure bugfixes upstream." We do not depend on upstream accepting anything. We ship independently.
>
> Current authoritative direction for v0.1: **[2026-07-01-phase0-v01-recommendations.md](../verification/2026-07-01-phase0-v01-recommendations.md)**.
>
> ### Revised phase structure (adopted 2026-07-01)
>
> The v1 spec collapsed "package upstream" and "fix broken features" into a single "v0.1 packaging" phase, which understated the code work needed. Current model:
>
> | Phase | Focus | Deliverable |
> |---|---|---|
> | **Phase 0** ✅ done | Verify upstream on FA507NV | Verification report + recommendations |
> | **Phase 1 — The Fork** | Code fixes and feature restoration | Patched asusd/asusctl/supergfxd binaries with all shipping features working on FA507NV. Our `patches/` quilt series maintained. |
> | **Phase 2 — The Packaging** | `debian/` + PPA + CI + docs | Users `sudo apt install asusctl-suite` on Jammy/Noble. Launchpad PPA live. |
> | **Phase 3 — The GUI** | GTK4+libadwaita Rust GUI | Visual control center, Armoury-Crate-equivalent UX. |
> | **Phase 4 — Distro Expansion** | Ubuntu 26.04, Debian bookworm/trixie | Broader user base, wider support matrix. |
>
> Phase 1 subsumes what the v1 spec called v0.1's "packaging strategy" — no, that was code work masquerading as packaging. Phase 2 is the real packaging. Phase 3 and Phase 4 map directly to v1's v0.2 and v0.3 respectively.
>
> Sections not listed above (repo layout, GUI plan, testing strategy, Ubuntu version target, BIOS handling, rollback safety) remain valid unchanged.

---

---

## 1. Purpose

Deliver a clean, `apt`-installable ASUS control stack for Ubuntu 22.04 (Jammy) and 24.04 (Noble) LTS users. Package the upstream OGC asusctl and supergfxctl projects without forking their Rust code, add a Ubuntu-native GTK4+libadwaita GUI, and publish via a Launchpad PPA.

Target user: ASUS TUF and ROG owners on Ubuntu LTS who currently have no clean install path. Test hardware: ASUS TUF Gaming A15 FA507NV.

## 2. Goals and non-goals

**Goals:**

- Users can `apt install asusctl-suite` and get a working thermal profile, fan curve, keyboard backlight, battery threshold, and GPU mode switch experience on Jammy and Noble.
- Zero source-building required for end users. No `cargo`, no `rustup`, no manual systemd unit copying.
- Native Ubuntu integration: AppArmor profiles, gdm3 handling for GPU switch, coexistence with `nvidia-prime`, dbus policies matching Ubuntu conventions.
- Custom GTK4+libadwaita GUI in v0.2 that meets a modern design bar (native GNOME feel, adaptive layouts).
- Additive upstream relationship: we contribute pure bugfixes to OGC via clean PRs, we keep Ubuntu specifics downstream in our `debian/` and `patches/`.
- Rollback safety on every package that touches sysfs, boot, or kernel state.

**Non-goals for v0.1:**

- No Debian bookworm/trixie packages (deferred to v0.3).
- No Ubuntu 26.04 Resolute support (deferred to v0.3).
- No GUI in v0.1 — custom GUI is deferred to v0.2.
- No `rog-control-center` shipping ever (skipped entirely per design decision — we build our own GUI in v0.2 instead).
- No AniMe Matrix or per-key RGB support (hardware not present on TUF).
- No Rust source patches beyond small, upstreamable bugfixes.

## 3. Strategic context

Research on 2026-07-01 established:

- Upstream moved from `gitlab.com/asus-linux/*` (archived) to `github.com/OpenGamingCollective/asusctl` (active, latest `v1.0.1`).
- Upstream is not accepting Ubuntu patches: PR #111 (a well-formed Jammy build patch by user `wing-kit`) was closed unmerged on 2026-06-20.
- Zero maintained PPA coverage exists for Jammy + Noble. `ppa:hantarex/asusctl` targets 25.10 + 26.04 only. `ppa:mitchellaugustin/asusctl` is 75 weeks dead.
- `asus-armoury` mainlined in Linux 6.19 (Dec 2025). Ubuntu 22.04 (kernel 6.8) and 24.04 (6.8/6.11) do not have it. DKMS backport required for feature parity.
- Fork is off the table: small community just consolidated onto OGC, forking again fragments it.
- Downstream packaging layer + DKMS is the empty niche and shortest defensible path.

## 4. Approach

Pure downstream packaging layer. We do not fork the upstream Rust codebase. We consume OGC's tagged release tarballs and produce Debian source packages that build them for Jammy and Noble on Launchpad's infrastructure.

Ubuntu specifics — gdm3 handling, AppArmor, nvidia-prime coexistence, systemd unit paths — live entirely in our `debian/` control files, postinst hooks, config templates, and policy files. No custom daemon in v0.1. If v0.2 or later uncovers behavior we cannot express as config, we add a small helper binary at that time, not before.

The `asus-armoury` sysfs driver (mainlined in 6.19) is backported as a DKMS package for Ubuntu's 6.8 / 6.11 kernels, gated on kernel version detection so it skips itself when the running kernel already provides the driver in-tree.

## 5. Repo layout

```
asusctl-ubuntu/
├── packages/
│   ├── asusctl/debian/            # asusctl + asusd source package
│   ├── supergfxctl/debian/        # supergfxctl + supergfxd source package
│   ├── asus-armoury-dkms/         # DKMS: uejji/asus-armoury backport
│   │   ├── debian/
│   │   └── src/                   # imported from uejji, pinned commit hash
│   ├── asusctl-gui/               # v0.2: our custom GTK4+libadwaita GUI (Rust)
│   │   ├── debian/
│   │   └── src/
│   └── asusctl-suite/debian/      # meta-package (depends on all the above)
├── patches/                        # quilt patches applied to upstream tarballs
├── scripts/
│   ├── fetch-upstream.sh          # pulls tagged tarballs from OGC
│   ├── build-all.sh               # local test build with pbuilder
│   └── publish-ppa.sh             # dput to Launchpad
├── docs/
│   ├── install.md                 # user-facing PPA setup
│   ├── troubleshoot.md            # per-model quirks, ACPI errors, NVIDIA crash notes
│   └── superpowers/specs/         # design docs (this file)
├── .github/workflows/             # CI: build + lintian on Jammy + Noble
└── README.md
```

## 6. Release phases

| Phase | Deliverable | Estimated part-time scope |
|---|---|---|
| **Phase 0** | Upstream verification on FA507NV. `cargo build` OGC v1.0.1 asusctl + supergfxctl. Manually test every v0.1 feature. Record what works, what breaks, what needs a patch. No packaging until this passes. | 1-2 sessions |
| **v0.1** | Jammy + Noble PPA. `asusctl`, `supergfxctl`, `asus-armoury-dkms`, `asusctl-suite` meta-package. No GUI. | 2-4 weeks |
| **v0.2** | Custom GTK4+libadwaita GUI (`asusctl-gui`) added. `asusctl-suite` gains GUI dependency. | 6-10 weeks (real design work) |
| **v0.3** | Ubuntu 26.04 Resolute + Debian bookworm/trixie support added. | 2-3 weeks |

Later phases handle GUI iteration, more distros, and any features that emerge from user feedback.

## 7. Package details

### 7.1 asusctl source package

Ships:

- `/usr/bin/asusctl` — CLI
- `/usr/bin/asusd` — daemon
- `/lib/systemd/system/asusd.service` — systemd unit
- `/usr/share/dbus-1/system.d/asusd.conf` — dbus policy
- `/lib/udev/rules.d/99-asusctl.rules` — device access rules
- `/etc/apparmor.d/usr.bin.asusd` — AppArmor profile
- `/etc/asusctl/` — config templates
- `/usr/share/doc/asusctl/` — docs

Build-depends: `cargo`, `rustc >= 1.82`, `libudev-dev`, `pkg-config`, `libclang-dev`, `libinput-dev`.

Postinst: enable and start `asusd.service`, reload AppArmor.

### 7.2 supergfxctl source package

Ships:

- `/usr/bin/supergfxctl` — CLI
- `/usr/bin/supergfxd` — daemon
- `/lib/systemd/system/supergfxd.service` — systemd unit
- `/etc/supergfxd.conf` — config with `DisplayManager=gdm3` pinned for Ubuntu
- dbus policy, apparmor profile

Postinst: check for `nvidia-prime` presence, log warning if both are active but do not disable either. Enable systemd unit.

### 7.3 asus-armoury-dkms source package

- Imports `uejji/asus-armoury` at a pinned commit hash.
- DKMS build hooks for kernels 6.8, 6.11.
- Skip logic: if running kernel is 6.19+, the DKMS package installs but the build is a no-op (kernel already has the driver in-tree).
- Blacklist logic: if the in-tree module is loaded, DKMS skips loading its version to avoid conflict.

### 7.4 asusctl-suite meta-package

Zero binaries. Just a `debian/control` with `Depends:` on the three constituent packages. Concrete minimum version constraints (`>= X.Y.Z`) are pinned during v0.1 packaging once upstream tarball versions are chosen. In v0.2, this meta-package gains `asusctl-gui` as a dependency.

## 8. GUI plan (v0.2)

### 8.1 Toolkit choice

GTK4 + libadwaita via `gtk4-rs` bindings. Selected for:

- Native Ubuntu / GNOME feel (Ubuntu ships GNOME by default).
- Modern adaptive design system.
- Well-documented, real-world design references (GNOME Files, GNOME Software, Fractal, Loupe).
- Rust throughout — keeps the stack unified with upstream.

Rejected alternatives: Slint (upstream's choice, feels non-native on GNOME), Iced (fully custom, high effort), Tauri (web stack overhead), Qt (foreign on GNOME).

### 8.2 Architecture

The GUI is a pure dbus client. It does not reimplement any daemon logic. It communicates with `asusd` and `supergfxd` over the system bus via `zbus`. If a daemon is not running, the GUI shows an error state and offers `systemctl start` guidance rather than trying to auto-start.

### 8.3 File structure

Respects the 300-line hard limit from `CLAUDE.md`:

```
asusctl-gui/src/
├── main.rs                      # entry point, ~30 lines
├── app.rs                       # AdwApplication object, ~150 lines
├── window.rs                    # AdwApplicationWindow, ~200 lines
├── pages/
│   ├── thermal.rs               # thermal profile picker
│   ├── fans.rs                  # fan curve editor
│   ├── gpu.rs                   # supergfxctl mode switcher
│   ├── battery.rs               # charge threshold slider
│   └── keyboard.rs              # backlight brightness
├── dbus/
│   ├── asusd_client.rs          # zbus proxy to asusd
│   └── supergfxd_client.rs      # zbus proxy to supergfxd
└── widgets/
    ├── fan_curve_graph.rs       # custom drawn fan curve widget
    └── profile_card.rs          # thermal profile card
```

One responsibility per file. Files that approach 250 lines are split proactively.

### 8.4 Design bar

Reference points: GNOME Settings, GNOME Software, Fractal. These are the visual and interaction quality bars we aim to match. The GUI is not a straight port of Armoury Crate — it is an Ubuntu-native app that provides equivalent functionality with a GNOME feel.

Detailed screen designs, layouts, typography, and color decisions are deferred to a separate design document during v0.2 planning.

## 9. Testing strategy

Real hardware only. FA507NV is the test rig. No VMs, no emulators (per `CLAUDE.md`).

Every feature is tested in four hardware states:

1. AC + idle
2. AC + GPU load (games or ML workload)
3. Battery + idle
4. Battery + GPU load

The four-state matrix catches power-transition bugs — specifically the NVIDIA ACPI hotplug crash pattern (documented in `project_nvidia_crash_pattern.md`). GPU mode switching is tested on AC power with an SSH session as safety net for the first several runs.

Cross-target validation for Noble packages happens via `pbuilder` or `schroot` on this Jammy machine — no dist-upgrade required.

## 10. Release and PPA

PPA: `ppa:baraka-malila/asus-linux` on Launchpad.

Launchpad builds source packages on their own infrastructure and produces binary `.deb` files for Jammy and Noble. Our dev machine only produces source packages via `dpkg-buildpackage -S` and uploads via `dput`. No local binary builds required.

CI: GitHub Actions builds each source package inside `pbuilder` chroots for Jammy and Noble, runs `lintian`, and reports failures on PR. Green CI is required before any PPA upload.

## 11. Upstream relationship

Additive and non-forking. We contribute:

- Pure bugfixes upstream via clean PRs on OGC (e.g. issue #132's `break`→`continue` fix in the asus-armoury registration cascade).
- No Ubuntu-specific PRs — upstream just rejected PR #111 for this exact reason. Ubuntu specifics stay in our `debian/` and `patches/`.

If upstream releases a new tag, we bump our packaging, rebuild, and re-upload. Estimated cost per upstream release: 1-2 hours.

## 12. Rollback safety

Every package that touches sysfs, systemd, or kernel state supports clean `dpkg --purge`. Explicit rollback checks:

- `asusd.service` is disabled and removed on purge.
- Config files under `/etc/asusctl/` and `/etc/supergfxd.conf` are preserved on remove, deleted on purge.
- The DKMS module is unloaded and removed on purge.
- No package touches kernel command line, EFI, or GRUB.

## 13. Compatibility with existing FA507NV state

This machine already has:

- `/etc/modprobe.d/nvidia-custom.conf` — custom NVIDIA options
- `/etc/systemd/system/battery-charge-threshold.service` — battery cap at 80%
- Kernel cmdline: `acpi_osi=Linux acpi_backlight=native nvidia_drm.modeset=1 pcie_aspm=off`

Our packaging respects these:

- We do not overwrite `/etc/modprobe.d/nvidia-custom.conf`.
- The `asusctl` package detects the pre-existing battery-charge-threshold systemd unit and logs a warning during postinst rather than fighting it. Migration to asusctl-native battery threshold management is offered but not automatic.
- We do not modify the kernel cmdline.

## 14. Ubuntu version target

**v0.1 targets Jammy (22.04) and Noble (24.04) only.**

Rationale:

- LTS versions are what the target audience (East Africa / South Asia / LatAm) uses.
- Interim releases (25.10 Questing) end July 2026 — not stable for the audience.
- Ubuntu 26.04 Resolute is ~3 months old at project start; its kernel likely has `asus-armoury` mainlined (6.19+), which changes the DKMS story. Handled separately in v0.3.

Dev machine stays on Jammy for the project. No dist-upgrade planned.

## 15. BIOS

Current BIOS on FA507NV: `FA507NV.316` (dated 2024-11-04). A newer BIOS is available via ASUS EZ Flash 3 with a `.CAP` file from ASUS support.

**BIOS upgrade is deferred to post-v0.1.** Rationale:

- Our packaging does not depend on BIOS behavior. We package software that talks to the kernel; the kernel talks to BIOS.
- BIOS flashes carry brick risk on a daily driver.
- Post-v0.1 BIOS flash becomes a useful regression test — does our stuff still work on new BIOS?

## 16. Open questions

- Final repo/org name (`github.com/Baraka-Malila/asusctl-ubuntu` or an org).
- Exact `uejji/asus-armoury` commit to pin for the DKMS backport.
- Whether to bundle the existing NVIDIA modprobe workarounds as an optional package or leave them fully user-managed.
- Whether v0.2 GUI should include a fan curve editor with graphical drag-drop points or only preset selection.

These are decisions for the implementation planning phase, not blockers on the design.
