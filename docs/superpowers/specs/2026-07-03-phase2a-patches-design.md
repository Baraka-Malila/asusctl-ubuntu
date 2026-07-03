# Phase 2a — Rust patches + feature catalog Design Spec

**Date:** 2026-07-03
**Depends on:** Phase 1 (tag `phase1-v0.1-fork`), specifically the sysfs power watcher patch (`patches/asusctl/0001-power-source-sysfs-watcher.patch`).
**Blocks:** Phase 2b (Debian packaging) — patches ship in the fork's `patches/asusctl/series` and freeze before Phase 2b turns them into .deb postinst/upstream tarball.
**Hardware:** ASUS TUF Gaming A15 FA507NV (kernel 6.8, Ubuntu 22.04, systemd 249).

---

## 1. Purpose

Extend the fork's power-source-aware feature surface to match Armoury-Crate-parity on FA507NV. Three Rust patches, one research document. Deliberately does not touch Debian packaging, PPA setup, CI, or user docs — those are Phase 2b concerns, and separating them keeps the reliability bar high on the code changes (per user's Phase 2 kickoff message).

## 2. Scope

Four deliverables:

| # | Deliverable | Type | Estimated effort |
|---|---|---|---|
| 1 | `docs/superpowers/specs/2026-07-03-armoury-crate-parity-catalog.md` | Research doc | ~1 day |
| 2 | `patches/asusctl/0002-kbd-brightness-on-power.patch` | Rust patch | ~2 days |
| 3 | `patches/asusctl/0003-fan-curve-per-ac-dc.patch` | Rust patch | ~3-4 days |
| 4 | `patches/asusctl/0004-gpu-mode-per-power.patch` (+ possibly `patches/supergfxctl/0002-*.patch`) | Rust patch(es) | ~4-5 days |

Total: ~2-3 weeks part-time. Exit tag: `phase2a-v0.1-patches`.

### Out of scope

- Debian `debian/` control files, postinst/preinst hooks — Phase 2b.
- Launchpad PPA setup — Phase 2b.
- GitHub Actions CI (pbuilder Jammy/Noble) — Phase 2b.
- User docs (`install.md`, `troubleshoot.md`) — Phase 2b.
- GTK+libadwaita GUI — Phase 3.

## 3. Task 1 — Feature catalog

### Purpose

Authoritative reference: (a) informs Phase 3 GUI design so it exposes the right controls, (b) gives us confidence Phase 2a's 3-patch scope is complete — no headline Armoury Crate feature accidentally missed, (c) marketing / user-docs input for Phase 2b.

### Location

`docs/superpowers/specs/2026-07-03-armoury-crate-parity-catalog.md`.

### Format

Table with these columns (~22 rows initially, expandable):

| Column | Content |
|---|---|
| Feature | Armoury-Crate-named feature (e.g., "Fan curves per profile") |
| TUF FA507NV hardware presence | ✅ / partial / ❌ |
| Linux stack availability | asusd-native / kernel-`asus-armoury` (6.11+) / external (GameMode, fwupd) / N/A |
| Phase 2a delivers? | Yes (patch # or catalog only) / No (deferred to Phase 2b, 3, 4, or Won't-do) |
| Phase 3 GUI element | Toggle / slider / picker / advanced panel / N/A |

### Row inventory (initial)

Thermal profiles (Silent/Balanced/Turbo) · Fan curves per profile · Fan curves per (profile × power source) · CPU EPP mapping per profile · GPU mode (Standard/Eco/Ultimate) · GPU mode per power source · Battery charge limit · Battery oneshot · Battery calibration · Kbd backlight brightness · Kbd RGB effects · Aura power zones (awake/boot/sleep) · Kbd brightness per power source · Kbd auto-off after N min · Panel overdrive · Refresh rate lock on battery · PPT/TDP limits · GPU TGP / Dynamic Boost · Boot logo animation · Sonic Studio audio profiles · Microphone AI noise cancel · Game auto-detect · Per-app profile boost · Battery health mode · BIOS updates via fwupd.

### Discipline

Table stays tight — one row = one line. Narrative comments about the rationale for "won't-do" entries and "deferred" entries live in numbered footnotes below the table. No open questions in the catalog itself — those move to a "Follow-ups" section at end of the doc.

## 4. Task 2 — `kbd_brightness_on_power` patch

### Location

`fork/asusctl/asusd/src/config.rs` (schema) + `fork/asusctl/asusd/src/ctrl_platform.rs` (watcher hook). Export as `patches/asusctl/0002-kbd-brightness-on-power.patch`.

### Config schema additions

```rust
pub kbd_brightness_on_ac: KbdBrightness,      // default: Med
pub kbd_brightness_on_battery: KbdBrightness, // default: Low
pub change_kbd_brightness_on_power: bool,     // default: false — opt-in per project policy
```

`KbdBrightness` enum is Off/Low/Med/High and already exists elsewhere in the tree (either `rog-aura` or `rog-platform`); import rather than redefine.

### Watcher hook

Extend the sysfs power watcher we added in Task 9.5. When AC state changes AND `change_kbd_brightness_on_power == true`:

1. Look up target brightness from config (ac vs battery)
2. Call into the existing kbd LED controller (grep for `set_brightness` or `CtrlKbdBacklight` — the same call path the dbus method behind `asusctl leds set <level>` uses). If unclear at implementation time, fall back to a direct sysfs write to `/sys/class/leds/asus::kbd_backlight/brightness`
3. Log at debug level: `"sysfs power watcher: kbd brightness → {target}"`

### Interfaces

- Consumes: sysfs power watcher from Task 9.5 (0001-power-source-sysfs-watcher.patch)
- Produces: nothing later Phase 2a patches consume — this patch stands alone

### Verification

Live install on FA507NV; toggle config `change_kbd_brightness_on_power: true`; unplug AC → journal shows the debug line + `/sys/class/leds/asus::kbd_backlight/brightness` sysfs goes to Low; plug AC → same for Med. Restore config to `false`, verify no automation fires.

### Diff size expectation

~40 lines (10 config additions + 25 watcher-hook + 5 boilerplate).

## 5. Task 3 — `fan_curve_per_ac_dc` patch

### Discovery

asusd 6.3.8 already has `ac_profile_tunings: Tunings` and `dc_profile_tunings: Tunings` fields in `config.rs`. Default is `{Quiet: {enabled: false, group: {}}, Balanced: {enabled: false, group: {}}, Performance: {enabled: false, group: {}}}`. Fields exist but do nothing.

### Two changes needed

**1. Populate sensible defaults in `Config::default()`** for all six cells (3 profiles × 2 power sources):

| Cell | Suggested default curve |
|---|---|
| AC × Quiet | `fan_curves.ron`'s stored Quiet curve, unchanged |
| AC × Balanced | `fan_curves.ron`'s stored Balanced curve, unchanged |
| AC × Performance | `fan_curves.ron`'s stored Performance curve, unchanged |
| DC × Quiet | Quiet curve with -5°C temp thresholds shifted higher (fans engage later on battery) |
| DC × Balanced | Balanced curve with PWM ceiling capped at 80% of AC (reduce max fan RPM to save battery) |
| DC × Performance | Identical curve values to DC × Balanced (on battery, "Performance" degrades to Balanced-like fan behavior — matches user expectation of quieter operation on battery). CPU EPP stays `performance` per the profile so it's not a full downgrade — just fan management. |

All six default to `enabled: false` so behavior is identical to today unless user opts in.

**2. Wire the tunings into `update_policy_ac_or_bat`** — on power-source change, if `enabled: true` for the (profile × power-source) cell, write that curve to hwmon instead of the profile's default curve.

Bridge or refactor if `Tunings` struct's internal type doesn't match what `write_profile_curve_to_platform` expects. Preserve the daemon's existing `enabled: false` no-op path so opting out is trivial.

### Interfaces

- Consumes: sysfs power watcher from Task 9.5.
- Produces: nothing later Phase 2a patches consume.

### Verification

`stress-ng --cpu 8 --timeout 60s` on FA507NV in each of the 6 cells (3 profiles × AC/battery). Read `/sys/class/hwmon/hwmon5/fan{1,2}_input` under load, verify RPMs track the specific per-cell curve. Toggle `enabled: false`/`true` per cell and confirm baseline vs custom behavior differs.

### Diff size expectation

~60 lines (30 config defaults + 25 wire-in logic + 5 boilerplate).

## 6. Task 4 — `gpu_mode_per_power` patch

### Config schema additions in asusd

```rust
pub gpu_mode_on_ac: GfxMode,                  // default: Hybrid
pub gpu_mode_on_battery: GfxMode,             // default: Integrated
pub change_gpu_mode_on_power: bool,           // default: false — opt-in
```

`GfxMode` enum lives in `supergfxctl` (Integrated/Hybrid/AsusMuxDgpu). asusd 6.3.8 vendors `supergfxctl 5.2.7` as a git dep at build time (Task 2 discovery), so the import path already exists.

`AsusMuxDgpu` is **excluded** as a valid target in the automation code path — it's reboot-required, not session-required, and auto-triggering a reboot on AC change is a hostile UX. Validate at config-load time; on a config file containing `gpu_mode_on_ac: AsusMuxDgpu`, warn and downgrade to `Hybrid`.

### Cross-daemon coordination

**Chosen approach: asusd → supergfxd via dbus** (rejected alternatives in Section 8).

asusd already uses `zbus` for its own dbus interface. Add a lightweight `supergfxd` proxy in the same style (`asusd/src/supergfxd_client.rs`, new file, ~40 lines) that:

1. Connects to system dbus on daemon startup.
2. Exposes an async `set_mode(mode: GfxMode)` method that calls `org.supergfxctl.Daemon.SetMode` (or whatever the exact interface name is — confirmed at implementation time by introspecting the running supergfxd).
3. Returns the supergfxd response (which includes the "pending action = logout" info supergfxctl CLI shows).

Called from the sysfs power watcher in ctrl_platform.rs when AC state changes and `change_gpu_mode_on_power == true`.

### Session UX

1. supergfxd stages the mode change with its existing "logout required" behavior. Phase 0 verified this is FA507NV-safe.
2. Fire a desktop notification via freedesktop's `org.freedesktop.Notifications` (asusd already has zbus so this is one more proxy):
   > "asusd: GPU mode change queued to {mode}. Log out to apply."
3. If the user doesn't want the change, they cancel via `supergfxctl -m {current-mode}` before logout — Task 8 verified cancellation works.
4. On next AC transition while pending, asusd re-queues if the target changed (idempotent — supergfxd handles this).

### Possible supergfxctl patch

If supergfxd's dbus interface doesn't expose `SetMode` cleanly, add `patches/supergfxctl/0002-expose-setmode-dbus.patch` to expose it. Investigation happens at implementation time; catalog this as a possibility, not a guaranteed patch.

### Interfaces

- Consumes: sysfs power watcher from Task 9.5.
- Produces: user-facing dbus notification, supergfxd queued mode change.

### Verification

Toggle `change_gpu_mode_on_power: true`, unplug AC, verify within ~5 seconds:
- supergfxd journal: `Switching gfx mode to Integrated`
- `supergfxctl -g` still shows current mode (live unchanged)
- `supergfxctl` shows pending action = "Logout required"
- Desktop notification appeared
- Re-issuing `supergfxctl -m {current}` cancels cleanly.

Reboot-cycle verification of the full switch is intentionally skipped — Task 8 already covered end-to-end mode switching including AsusMuxDgpu. This task verifies the *trigger*, not the switch mechanism.

### Diff size expectation

~100 lines in asusctl (60 client + 30 watcher hook + 10 config). Possibly ~15 lines in supergfxctl if `SetMode` dbus needs exposing.

## 7. Task order + verification discipline

### Order

1. Feature catalog first (docs-only; also lets us confirm patch scope 2-4 is complete).
2. Kbd brightness (smallest, cleanest patch).
3. Fan curves per AC/DC (medium — the tunings semantics wrinkle).
4. GPU mode per power (largest — cross-daemon).

Sequential, not parallel. Each patch depends on the prior being applied to the fork tree before format-patch export.

### Discipline (unchanged from Phase 1)

- Feature branch per task: `phase2a/task-N-<slug>`
- Verify on FA507NV four-state matrix (AC+idle, AC+load, batt+idle, batt+load)
- Include an on-transition test (unplug/plug)
- Cool-down: session teardown after each verification restores pre-flight snapshot
- PR-only workflow: user reviews and merges, never automated
- Every PR references the feature catalog for context

### Exit criteria

- Feature catalog authored + PR merged
- 3 new patches applied cleanly on top of 0001-power-source-sysfs-watcher
- `scripts/build-fork-asusctl.sh` produces a working binary with the full series
- Each feature verified working on FA507NV per its verification section
- Tag `phase2a-v0.1-patches` applied to main after all PRs are merged

## 8. Rejected alternatives

**Config-schema-first approach (all fields in one patch, then wire each).** Rejected — over-designs upfront, forces schema decisions before we see any of them work in isolation. Phase 1's rhythm (one feature = one patch, wired end-to-end) proved higher-quality; keeping it.

**GPU mode via asusd forking `supergfxctl` binary.** Rejected as primary — dbus proxy is architecturally cleaner and avoids process-spawn overhead on every AC transition. Reserved as fallback if dbus turns out to have interface complications.

**Ship GPU-mode-per-power enabled by default.** Rejected — logout-required, user-session-disruptive. Matches how Armoury Crate on Windows keeps it opt-in even where the OS could handle it live. See section 6.

**Fold feature catalog into a subsection of an existing spec.** Rejected — catalog is 22+ rows and needs its own doc for Phase 3 GUI reference and Phase 2b user docs to link to.

## 9. Open decisions (deferred to implementation time)

- Exact dbus method name / interface name on supergfxd for `SetMode` — needs live introspection of the running fork's supergfxd.
- Whether `Tunings` type in asusd's config bridges cleanly to `write_profile_curve_to_platform`'s expected input, or whether a small conversion helper is needed.
- Whether `AsusMuxDgpu` config-value should error at load time, silently downgrade to Hybrid with a warn!, or be accepted-but-ignored. Recommend warn+downgrade.
- Desktop notification wording — 1-line variants for AC-connect vs battery-disconnect.

None are scope-changing; each is a small local implementation decision.
