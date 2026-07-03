# Armoury Crate → Linux Parity Catalog

**Date:** 2026-07-03
**Scope:** ASUS TUF Gaming A15 FA507NV as the reference hardware. Other TUF / ROG models add or remove rows (per-key RGB, AniMe Matrix, Slash bar, screenpad).
**Purpose:**
- Anchors Phase 3 GUI design so it exposes the correct controls, no more and no less.
- Validates Phase 2a's 3-patch scope is complete — nothing headline that Armoury Crate offers on TUF hardware is missed.
- Sourced by Phase 2b's user-facing `install.md` / `troubleshoot.md` and future marketing.

## Column key

| Column | Domain |
|---|---|
| **Feature** | Armoury-Crate-canonical name (Windows-side UX) |
| **HW presence FA507NV** | ✅ (present) / partial / ❌ (absent) |
| **Linux stack availability** | `asusd-native` / `kernel-asus-armoury (6.11+)` / `external:GameMode` / `external:fwupd` / `N/A on Linux` |
| **Phase 2a delivers?** | catalog only / patch 0002 / patch 0003 / patch 0004 / Phase 1 (shipped) / Phase 2b / Phase 3 / Phase 4 / **Won't-do** |
| **Phase 3 GUI element** | toggle / slider / picker / advanced panel / N/A |

## Catalog

| Feature | HW presence FA507NV | Linux stack availability | Phase 2a delivers? | Phase 3 GUI element |
|---|---|---|---|---|
| Thermal profile (Silent / Balanced / Turbo) | ✅ | asusd-native | Phase 1 (shipped) | picker |
| CPU EPP mapping per thermal profile | ✅ | asusd-native | Phase 1 (shipped) | advanced panel |
| Fan curve per profile | ✅ | asusd-native | Phase 1 (shipped) | curve editor |
| Fan curve per (profile × power source) | ✅ | asusd-native | patch 0003 | curve editor |
| GPU mode (Standard = Hybrid / Eco = Integrated / Ultimate = AsusMuxDgpu) | ✅ | asusd-native (via supergfxd) | Phase 1 (shipped, Task 8) | picker |
| GPU mode auto-switch per power source | ✅ | asusd-native (via supergfxd) | patch 0004 | toggle + picker (per state) |
| Battery charge limit | ✅ | asusd-native | Phase 1 (shipped) | slider |
| Battery one-shot full charge | ✅ | asusd-native | Phase 1 (shipped) | button |
| Battery calibration | ✅ | asusd-native (oneshot round-trip) | Phase 1 (shipped) [1] | advanced panel |
| Keyboard backlight brightness | ✅ | asusd-native | Phase 1 (shipped) | slider |
| Keyboard RGB effects (Static / Breathe / RainbowCycle / RainbowWave / Pulse) | ✅ 5 modes | asusd-native | Phase 1 (shipped, verified in Task 9.5) | picker + color |
| Aura power zones (awake / boot / sleep) | ✅ (`aura power-tuf`) | asusd-native | Phase 1 (shipped) | toggles |
| Kbd brightness per power source (auto-dim on battery) | ✅ | asusd-native | patch 0002 | toggle + picker (per state) |
| Kbd auto-off after N min inactivity | ✅ | kernel (LED trigger) + userspace | Phase 3 [2] | slider (minutes) |
| Panel overdrive (response time toggle) | ✅ | kernel-asus-armoury (6.11+) | Phase 2b (`asus-armoury-dkms`) | toggle |
| Panel refresh rate lock on battery | ✅ | kernel-asus-armoury (6.11+) | Phase 2b (`asus-armoury-dkms`) | picker |
| PPT / CPU sustained-TDP limit | ✅ | kernel-asus-armoury (6.11+) | Phase 2b (`asus-armoury-dkms`) | slider (watts) |
| GPU TGP / Dynamic Boost | ✅ | kernel-asus-armoury (6.11+) | Phase 2b (`asus-armoury-dkms`) | slider (watts) |
| Boot logo animation | ✅ | kernel-asus-armoury (6.11+) | Phase 2b (`asus-armoury-dkms`) | picker |
| Sonic Studio audio profiles | ✅ | N/A on Linux | **Won't-do** [3] | N/A |
| Microphone AI noise cancellation | ✅ | N/A on Linux | **Won't-do** [3] | N/A |
| Game auto-detect / Game profiles | ✅ | external:GameMode | Phase 3 [4] | advanced panel |
| Per-app profile boost | ✅ | external:GameMode | Phase 3 [4] | advanced panel |
| BIOS update from GUI | ✅ | external:fwupd (LVFS) | Phase 3 [5] | button + list |
| Backlight-shadow blacklist on FA507NV-family | (bug, not a feature) | packaging | Phase 2b [6] | advanced panel (undo button) |
| Wayland-on-NVIDIA opt-in | (bug, not a feature) | packaging | Phase 3 [7] | toggle (experimental) |

## Footnotes

[1] **Battery calibration** works via `asusctl battery oneshot <target>` — Phase 1 Task 9.5 validated the `oneshot 100` path. The Armoury-Crate "Battery Health" panel wraps this pattern; our GUI in Phase 3 does the same.

[2] **Kbd auto-off after inactivity** exists in the Linux kernel as an LED trigger (`echo backlight > /sys/class/leds/asus::kbd_backlight/trigger` on some hardware), but GNOME's power settings expose this less cleanly than a dedicated GUI slider would. Phase 3 GUI implements a userspace watcher (idle-time-based) that switches kbd off/on via the asusd LED interface. Doesn't need a new asusd config field.

[3] **Sonic Studio / AI noise cancel** are Windows-only DSP driver stacks bundled by ASUS. Linux equivalents (PulseAudio EQ modules, RNNoise plugins, EasyEffects) already exist as first-class packages and aren't ours to ship. Documentation in Phase 2b's `troubleshoot.md` can point users there.

[4] **Game auto-detect / per-app boost** on Linux is handled by `feralinteractive/gamemode`. It's a well-authenticated daemon (user opts in via `LD_PRELOAD=libgamemode.so.0`, Steam integrates natively). Phase 3 GUI wires our profile-picker to gamemode's dbus signals so that profile auto-switches when a registered game is running. Not our fork's job to reinvent.

[5] **BIOS update from GUI** requires a LVFS entry for the specific board. FA507NV currently has no LVFS entry (memory: `project_bios_update_pending.md`); users are stuck on EZ Flash 3. Phase 3 GUI exposes `fwupdmgr get-devices` output; if a LVFS entry exists it becomes clickable, otherwise it shows a helpful "BIOS update via EZ Flash 3" pointer.

[6] **Backlight-shadow blacklist** — Phase 2b design already exists at `docs/superpowers/specs/2026-07-03-backlight-shadow-blacklist.md`. Deb postinst detects FA507NV-family (both `amdgpu_bl*` and `nvidia_0` present under expected paths) and installs `/etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf` + `update-initramfs -u`.

[7] **Wayland-on-NVIDIA opt-in** is a workaround for Ubuntu 22.04 GDM disabling Wayland on NVIDIA-only setups. Deferred to Phase 3 as an "experimental" toggle — deleting `/etc/udev/rules.d/61-gdm.rules` and setting `WaylandEnable=true` in `/etc/gdm3/custom.conf`. Not a default; the NVIDIA/Wayland combination has known warts on kernel 6.8.

## Follow-ups

Not classified definitively at design time — each becomes a GitHub issue for research before Phase 3 GUI:

- **Aura per-key RGB on ROG models** — FA507NV has single-zone TUF keyboard, so N/A for this hardware but relevant for ROG owners. Catalog does not attempt to enumerate ROG-specific effects/modes; Phase 4 (distro expansion) may bring ROG hardware into test coverage.
- **AniMe Matrix / Slash bar** on ROG G-series — same as above. N/A for FA507NV.
- **Screenpad brightness / gamma** — N/A for FA507NV, present on ROG Zephyrus Duo. `asusctl backlight` subcommand exists; leaving in catalog would clutter FA507NV column.
- **Manual fan curve during real-time gaming** — Armoury Crate on Windows adjusts fan curves live during gameplay based on temperature history. Our fan curve editor writes to `hwmon`; kernel EC drives the actual response. Whether there's a meaningful "AI-driven" adjustment layer on top isn't decided yet.
- **Aura sync with external RGB devices** — Windows Armoury Crate syncs to Aura-branded peripherals (mice, headsets). Linux: `OpenRGB` project handles this. Almost certainly out of scope for our fork; note for Phase 3 docs.

## Interpretation

**Phase 2a code work covers 3 rows** in the catalog: fan curve per (profile × power source), GPU mode auto-switch per power source, kbd brightness per power source. Every other row in the catalog is either shipped (Phase 1), deferred to a later phase, or documented as won't-do.

**No Armoury Crate feature that FA507NV hardware supports is silently missing** from this catalog. If a reviewer discovers one, it's added as a table row and the responsible phase is determined; PR against this doc, not against a patch.
