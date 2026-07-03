# Phase 2a — Rust patches + feature catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the fork's power-source-aware feature surface to Armoury-Crate parity on FA507NV via three Rust patches (`patches/asusctl/0002`, `0003`, `0004`) applied on top of Phase 1's `0001-power-source-sysfs-watcher`, plus a feature catalog document that anchors Phase 3 GUI design.

**Architecture:** Reuse the sysfs power watcher landed in Phase 1 Task 9.5 as the single power-transition hook — extending it in place rather than adding new watchers keeps event handling coherent and idempotent. New config fields default to `change_*_on_power: false` (opt-in) so behavior is identical to today unless the user turns each on. GPU mode auto-switch calls supergfxd via a new zbus proxy; the mode change is queued (session-safe), the user logs out to apply. Each patch stands alone: reviewer can merge in isolation, patches don't consume each other's outputs beyond the shared `0001` watcher.

**Tech Stack:** Rust ≥ 1.82, tokio, zbus 5.x, RON config, kernel sysfs (`/sys/class/power_supply/`, `/sys/class/hwmon/`, `/sys/class/leds/`), FA507NV hardware. Ubuntu 22.04 host.

## Global Constraints

- File length hard limit: 300 lines (CLAUDE.md rule 1) — applies to code and shipping artifacts; **this plan and design specs are exempt** (memory: `feedback_file_length_scope.md`).
- One responsibility per file (CLAUDE.md rule 2).
- Real hardware only — no VMs (CLAUDE.md testing rule).
- Preserve existing FA507NV state unless a task explicitly migrates it.
- **Independent fork model** (memory: `feedback_independent_fork.md`). Every feature we add is a real feature, not a demo — verified end-to-end on FA507NV before PR.
- **PR-and-merge workflow** (memory: `feedback_workflow.md`). Every task ends with `gh pr create` on a feature branch `phase2a/task-N-<slug>`. Never `gh pr merge`.
- **Opt-in default for every new automation.** `change_kbd_brightness_on_power`, `change_gpu_mode_on_power` default to `false`. Fan-curve-per-power `enabled: false` per cell. Users know they turned it on. Matches Armoury Crate on Windows behavior for GPU auto-switch (spec §2, §6, §8).
- Fork base tag is **6.3.8** (Phase 1 Task 2 decision). Every code path references match the 6.3.8 layout observed in `upstream/asusctl/asusd/src/`.
- Every patch task ends by exporting via `git -C fork/asusctl format-patch fork/base..HEAD --start-number N -o ../../patches/asusctl/` and appending the resulting file name to `patches/asusctl/series`.
- Every patch task's verification includes the four-state matrix (AC+idle, AC+load, batt+idle, batt+load) for the relevant feature, plus at least one live AC transition to prove the sysfs watcher fires.
- `AsusMuxDgpu` must never be auto-selected as a `gpu_mode_on_*` target (reboot-required, hostile UX per spec §6). Guarded at config load and at runtime.

---

## Files & Structure

**Created / committed by this plan:**

- `docs/superpowers/specs/2026-07-03-armoury-crate-parity-catalog.md` — Task 1 feature catalog
- `patches/asusctl/0002-kbd-brightness-on-power.patch` — Task 2 export
- `patches/asusctl/0003-fan-curve-per-ac-dc.patch` — Task 3 export
- `patches/asusctl/0004-gpu-mode-per-power.patch` — Task 4 export
- `docs/superpowers/verification/2026-07-03-phase2a-verify-taskN.md` for each task's on-hardware log

**Modified in fork tree (each becomes a patch entry):**

- `fork/asusctl/asusd/src/config.rs` — Tasks 2, 3, 4 add config fields
- `fork/asusctl/asusd/src/ctrl_platform.rs` — Tasks 2, 3, 4 extend the sysfs power watcher (spawned at line ~980, added in Phase 1)
- `fork/asusctl/asusd/src/supergfxd_client.rs` — Task 4 creates (new file, ≤ 300 lines, one responsibility)
- `fork/asusctl/asusd/src/notification_client.rs` — Task 4 creates (new file, ≤ 300 lines)
- `fork/asusctl/asusd/src/lib.rs` — Task 4 registers the two new modules
- `patches/asusctl/series` — appended once per task

**Gitignored (unchanged from Phase 1):** `upstream/`, `fork/`, `/var/lib/asus-phase1-fork/`.

---

## Pre-flight state snapshot (before Task 1)

```bash
mkdir -p /tmp/asus-phase2a-snapshot
cat /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy > /tmp/asus-phase2a-snapshot/thermal 2>/dev/null || true
cat /sys/class/power_supply/BAT1/charge_control_end_threshold  > /tmp/asus-phase2a-snapshot/charge  2>/dev/null || true
cat /sys/class/leds/asus::kbd_backlight/brightness             > /tmp/asus-phase2a-snapshot/kbd     2>/dev/null || true
cat /proc/cmdline                                              > /tmp/asus-phase2a-snapshot/cmdline
cp /etc/modprobe.d/nvidia-custom.conf /tmp/asus-phase2a-snapshot/ 2>/dev/null || true
systemctl is-enabled battery-charge-threshold.service          > /tmp/asus-phase2a-snapshot/batsvc  2>/dev/null || true
supergfxctl -g 2>/dev/null > /tmp/asus-phase2a-snapshot/gpu_mode || echo "supergfxctl absent" > /tmp/asus-phase2a-snapshot/gpu_mode
```

Task 4 diffs against this at end.

**Also refresh the fork:** the fork trees still hold the tip from Phase 1 Task 9.5. Reset to the pristine fork/base tag + reapply the current series before starting so we're building on a known baseline.

```bash
cd /home/cyberpunk/asus
./scripts/build-fork-asusctl.sh 2>&1 | tail -5   # applies patches/asusctl/series (0001 only right now), rebuilds
./scripts/build-fork-supergfxctl.sh 2>&1 | tail -5   # applies patches/supergfxctl/series (0001 only), rebuilds
```

Both must finish with `Finished release [optimized] target(s)` and both binaries present.

---

### Task 1: Feature catalog

**Files:** Create `docs/superpowers/specs/2026-07-03-armoury-crate-parity-catalog.md`.

**Consumes:** Phase 1 outputs + design spec §3.

**Produces:** authoritative table of Armoury Crate features vs Linux availability, referenced by every subsequent Phase 2a PR + Phase 3 GUI planning + Phase 2b user docs.

- [ ] **Step 1: Author the catalog with a header + explanation of the table columns**

Section 1 of the doc explains: purpose (Phase 3 GUI reference + Phase 2a scope validation), format (table + footnotes), source (Armoury Crate Windows UX + FA507NV hardware). Section 2 is the table.

Section 2 columns exactly as spec §3 defines:

| Feature | TUF FA507NV hardware presence | Linux stack availability | Phase 2a delivers? | Phase 3 GUI element |

- [ ] **Step 2: Fill the table with the 22 rows from spec §3**

For each row, cell contents:

- **Feature**: Armoury-Crate-canonical name
- **Hardware presence**: ✅ (present) / partial / ❌ (absent). FA507NV notes: no AniMe Matrix, no Slash bar, no per-key RGB, no screenpad
- **Linux stack availability**: choose from `asusd-native`, `kernel-asus-armoury (6.11+)`, `external:GameMode`, `external:fwupd`, `N/A on Linux`
- **Phase 2a delivers?**: `catalog only`, `patch 0002`, `patch 0003`, `patch 0004`, `Phase 1 (already shipped)`, `Phase 2b`, `Phase 3`, `Phase 4`, `Won't-do`
- **Phase 3 GUI element**: `toggle`, `slider`, `picker`, `advanced panel`, `N/A`

- [ ] **Step 3: Add footnotes explaining every `Won't-do` and every `Phase 4+` row**

Rationale for each is one sentence. Example: "Sonic Studio: Windows-only DSP driver stack; Linux ALSA/PulseAudio equivalents already exist and don't need our shipping. Won't-do."

- [ ] **Step 4: Add a "Follow-ups" section** listing any Armoury Crate features we couldn't classify definitively at design time — one line each, with a link to the GitHub issue we should file to research.

- [ ] **Step 5: Cross-check patch scope**

Read the catalog end-to-end. Any row marked `patch 0002`, `patch 0003`, or `patch 0004` that this plan does NOT implement is a bug — add a task, or downgrade the row to `Phase 2b` / `Phase 3`. Any row that this plan implements which isn't in the catalog is also a bug — add the row.

- [ ] **Step 6: Feature branch → commit → PR**

```bash
git checkout main && git pull
git checkout -b phase2a/task1-catalog
git add docs/superpowers/specs/2026-07-03-armoury-crate-parity-catalog.md
git commit -m "Phase 2a Task 1: Armoury Crate parity catalog"
git push -u origin phase2a/task1-catalog
gh pr create --title "Phase 2a Task 1: feature catalog" \
    --body "Armoury Crate → Linux mapping table. 22 rows. Referenced by patches 0002–0004 + Phase 3 GUI + Phase 2b docs."
```

---

### Task 2: Patch — `kbd_brightness_on_power`

**Files:**
- Modify: `fork/asusctl/asusd/src/config.rs` (add three fields to `Config`)
- Modify: `fork/asusctl/asusd/src/ctrl_platform.rs` (extend the sysfs power watcher spawned in Phase 1)
- Create: `docs/superpowers/verification/2026-07-03-phase2a-verify-task2.md`
- Export: `patches/asusctl/0002-kbd-brightness-on-power.patch`
- Modify: `patches/asusctl/series`

**Consumes:** Phase 1's `0001-power-source-sysfs-watcher` patch (already in the fork tree via `build-fork-asusctl.sh`).

**Produces:** on AC/battery transition, if `change_kbd_brightness_on_power: true`, asusd writes the target brightness to `/sys/class/leds/asus::kbd_backlight/brightness`. No dependency on later tasks.

**Interfaces:**
- Consumes: `AsusPower::get_online() -> Result<u8>` from Phase 1 sysfs watcher. `Config` struct in `config.rs`.
- Produces: three new fields on `Config` — `kbd_brightness_on_ac: KbdBrightness`, `kbd_brightness_on_battery: KbdBrightness`, `change_kbd_brightness_on_power: bool`. Reused by no later task.

- [ ] **Step 1: Locate the KbdBrightness enum in the fork tree**

```bash
grep -rn "enum KbdBrightness\|enum LedBrightness\|enum Brightness" /home/cyberpunk/asus/fork/asusctl/rog-aura/src/ /home/cyberpunk/asus/fork/asusctl/rog-platform/src/ 2>/dev/null | head
```

Expected: an enum exists with variants like `Off`, `Low`, `Med`, `High`. Record the exact `use` path (e.g. `rog_aura::LedBrightness`).

If the grep returns nothing: define our own enum in `config.rs`:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
pub enum KbdBrightness {
    Off,
    Low,
    Med,
    High,
}

impl KbdBrightness {
    pub fn as_sysfs_value(self) -> u8 {
        match self {
            Self::Off => 0,
            Self::Low => 1,
            Self::Med => 2,
            Self::High => 3,
        }
    }
}
```

Update Step 3 accordingly.

- [ ] **Step 2: Add the three config fields to `Config` in `fork/asusctl/asusd/src/config.rs`**

Find the struct `Config` — currently ends around the `armoury_settings` field.

Add before the closing brace:

```rust
    // Kbd brightness auto-adjust on AC/battery. Opt-in per project policy
    // (change_kbd_brightness_on_power defaults to false). Introduced in
    // Phase 2a Task 2.
    #[serde(default = "default_kbd_brightness_on_ac")]
    pub kbd_brightness_on_ac: KbdBrightness,
    #[serde(default = "default_kbd_brightness_on_battery")]
    pub kbd_brightness_on_battery: KbdBrightness,
    #[serde(default)]
    pub change_kbd_brightness_on_power: bool,
```

Add helper functions BELOW the `impl Default for Config`:

```rust
fn default_kbd_brightness_on_ac() -> KbdBrightness { KbdBrightness::Med }
fn default_kbd_brightness_on_battery() -> KbdBrightness { KbdBrightness::Low }
```

Update `impl Default for Config` — the existing block returning `Config { ... }` — to include the three new fields with the defaults above (so a freshly created Config has the intended defaults, in addition to the serde-default fallback).

Add the appropriate `use` line at the top of `config.rs` for `KbdBrightness` (either from `rog_aura` per Step 1's grep, or your local definition).

- [ ] **Step 3: Extend the sysfs power watcher in `fork/asusctl/asusd/src/ctrl_platform.rs`**

Locate the `tokio::spawn` block introduced by `0001-power-source-sysfs-watcher.patch` (starts around line 985 with `let platform_sysfs = self.clone();`). Find the inner if-block that handles the "state changed" path — it currently calls `update_policy_ac_or_bat`, `run_ac_or_bat_cmd`, and conditionally `restore_charge_limit`.

Add this after the `run_ac_or_bat_cmd` call and BEFORE the `last_power_plugged` assignment (so we don't touch kbd if run_ac_or_bat_cmd errors):

```rust
                // Kbd brightness auto-adjust — Phase 2a Task 2. Opt-in.
                {
                    let cfg = platform_sysfs.config.lock().await;
                    if cfg.change_kbd_brightness_on_power {
                        let target = if plugged {
                            cfg.kbd_brightness_on_ac
                        } else {
                            cfg.kbd_brightness_on_battery
                        };
                        let value = target.as_sysfs_value();
                        debug!("sysfs power watcher: kbd brightness -> {:?}", target);
                        if let Err(err) = std::fs::write(
                            "/sys/class/leds/asus::kbd_backlight/brightness",
                            format!("{value}\n"),
                        ) {
                            warn!("Failed to write kbd_backlight brightness: {err}");
                        }
                    }
                }
```

Direct sysfs write (not a dbus roundtrip through the aura service) is deliberate — asusd is already root, the sysfs path is standard-kernel, and this keeps the change local to `ctrl_platform.rs` without touching the aura subsystem.

- [ ] **Step 4: Build the patched fork**

```bash
cd /home/cyberpunk/asus/fork/asusctl
git add asusd/src/config.rs asusd/src/ctrl_platform.rs
git commit -m "asusd: kbd brightness auto-adjust on AC/battery transitions

Adds kbd_brightness_on_ac, kbd_brightness_on_battery, and
change_kbd_brightness_on_power to the asusd config. When the opt-in
flag is true, the Phase 1 sysfs power watcher writes the corresponding
KbdBrightness value to /sys/class/leds/asus::kbd_backlight/brightness
on every AC state change.

Defaults: AC = Med, battery = Low. change_kbd_brightness_on_power
defaults to false (opt-in, matches project policy)."
cd /home/cyberpunk/asus
./scripts/build-fork-asusctl.sh 2>&1 | tail -8
```

Expected final lines: `2 patch(es) applied` then cargo `Finished release [optimized]`.

If cargo fails: read the error, fix, re-commit in the fork tree, re-run `build-fork-asusctl.sh`.

- [ ] **Step 5: Install and verify on FA507NV — AC+idle**

```bash
echo <sudo password> | sudo -S bash /home/cyberpunk/asus/scripts/install-fork-asusd-test.sh 2>&1 | tail -6
export PATH=/usr/local/bin:/usr/local/sbin:$PATH
# Enable the automation and pick observably different levels
sudo sh -c 'echo "  change_kbd_brightness_on_power: true," >> /etc/asusd/asusd.ron'   # or edit in place
sudo sh -c 'echo "  kbd_brightness_on_ac: High," >> /etc/asusd/asusd.ron'
sudo sh -c 'echo "  kbd_brightness_on_battery: Off," >> /etc/asusd/asusd.ron'
sudo systemctl restart asusd-test.service
sleep 2
sudo journalctl -u asusd-test.service --no-pager -n 20 | tail -10
```

**Important:** the exact way asusd.ron accepts new fields depends on RON syntax — a simpler alternative is to stop asusd, edit /etc/asusd/asusd.ron in-place with a text editor to set the three fields, then start asusd. Use whichever your engineer prefers.

Baseline: `cat /sys/class/leds/asus::kbd_backlight/brightness` → note the value.

- [ ] **Step 6: Verify on AC → battery transition**

Physically unplug AC. Within 5 seconds:

```bash
cat /sys/class/leds/asus::kbd_backlight/brightness   # expect 0 (Off)
sudo journalctl -u asusd-test.service --no-pager -n 10 | grep "kbd brightness"   # expect "kbd brightness -> Off"
```

- [ ] **Step 7: Verify on battery → AC transition**

Plug AC. Within 5 seconds:

```bash
cat /sys/class/leds/asus::kbd_backlight/brightness   # expect 3 (High)
sudo journalctl -u asusd-test.service --no-pager -n 10 | grep "kbd brightness"   # expect "kbd brightness -> High"
```

- [ ] **Step 8: Verify opt-out — set change_kbd_brightness_on_power: false, restart daemon, do one more AC transition. Expected: no journal line about kbd brightness, sysfs unchanged.**

- [ ] **Step 9: Record verification, teardown**

Write `docs/superpowers/verification/2026-07-03-phase2a-verify-task2.md`: paste the journal grep + sysfs values for each state transition. Note timing (typically 2-4s after unplug/plug).

```bash
sudo bash /home/cyberpunk/asus/scripts/phase1-teardown.sh
# Verify pre-flight state restored
diff <(cat /sys/class/leds/asus::kbd_backlight/brightness) /tmp/asus-phase2a-snapshot/kbd
```

- [ ] **Step 10: Export patch + PR**

```bash
git -C /home/cyberpunk/asus/fork/asusctl format-patch fork/base..HEAD --start-number 2 -o /tmp/
mv /tmp/0002-*.patch /home/cyberpunk/asus/patches/asusctl/0002-kbd-brightness-on-power.patch
echo "0002-kbd-brightness-on-power.patch" >> /home/cyberpunk/asus/patches/asusctl/series
cd /home/cyberpunk/asus
git checkout -b phase2a/task2-kbd-brightness
git add patches/asusctl/series patches/asusctl/0002-kbd-brightness-on-power.patch docs/superpowers/verification/2026-07-03-phase2a-verify-task2.md
git commit -m "Phase 2a Task 2: kbd brightness on power source"
git push -u origin phase2a/task2-kbd-brightness
gh pr create --title "Phase 2a Task 2: kbd brightness on power source" \
    --body "Adds change_kbd_brightness_on_power (opt-in), kbd_brightness_on_ac (default Med), kbd_brightness_on_battery (default Low). Verified on FA507NV AC↔battery transitions: sysfs 0 ↔ 3 within 2-4s of state change."
```

---

### Task 3: Patch — `fan_curve_per_ac_dc`

**Files:**
- Modify: `fork/asusctl/asusd/src/config.rs` (populate `Tunings` defaults for AC and DC across all three profiles)
- Modify: `fork/asusctl/asusd/src/ctrl_platform.rs` (wire tunings lookup into the sysfs power watcher AND into `apply_fan_curves_and_ppt`)
- Create: `docs/superpowers/verification/2026-07-03-phase2a-verify-task3.md`
- Export: `patches/asusctl/0003-fan-curve-per-ac-dc.patch`
- Modify: `patches/asusctl/series`

**Consumes:** Phase 1's `0001` and Task 2's `0002` in the series. asusd's existing `Tunings` type + its `select_tunings(power_plugged, profile)` method + `write_profile_curve_to_platform` (grep `rog_profiles` in the fork tree for the exact signature).

**Produces:** on AC/battery transition, `apply_fan_curves_and_ppt` selects the correct (profile × power source) fan-curve cell from the Tunings map (falls back to the profile's default curve if `enabled: false`). No dependency from Task 4.

**Interfaces:**
- Consumes: Phase 1 sysfs watcher, `PlatformProfile` enum (Quiet/Balanced/Performance), the existing `apply_fan_curves_and_ppt(&self, attrs, power_plugged, profile)` method.
- Produces: `Tunings` populated with concrete PWM/temp curves for 6 cells. Six cells all default to `enabled: false` (opt-in, per project policy).

- [ ] **Step 1: Inspect the existing Tunings + Tuning types in config.rs**

```bash
grep -n "struct Tunings\|struct Tuning\|type Tunings\|type Tuning\|pub group" /home/cyberpunk/asus/fork/asusctl/asusd/src/config.rs
grep -rn "select_tunings\|write_profile_curve_to_platform" /home/cyberpunk/asus/fork/asusctl/asusd/src/ /home/cyberpunk/asus/fork/asusctl/rog-profiles/src/ 2>/dev/null | head
```

Expected: `Tunings` is a HashMap<PlatformProfile, Tuning>; `Tuning` has fields `enabled: bool` and `group: HashMap<something, curve_data>`. Record the exact types.

If Tuning's group HashMap stores something OTHER than `CurveData { fan, pwm: [u8;8], temp: [u8;8], enabled: bool }`: adapt Step 3's code shape accordingly. The plan below assumes the standard CurveData shape.

- [ ] **Step 2: Populate default AC + DC tunings in `impl Default for Config`**

Replace the existing empty defaults for `ac_profile_tunings` and `dc_profile_tunings` with the concrete curves below. All six cells default `enabled: false` (opt-in). Values are derived from asusd 6.3.8's shipped `fan_curves.ron` (spec §5) with DC-side reduction.

```rust
fn ac_default_tunings() -> Tunings {
    use PlatformProfile::*;
    let mut map = HashMap::new();
    map.insert(Quiet, tuning_from_curves(
        &[(60,5),(63,22),(66,38),(69,45),(72,56),(75,63),(78,81),(78,81)], // CPU
        &[(58,5),(60,20),(63,38),(65,43),(67,56),(70,66),(72,84),(72,84)], // GPU
    ));
    map.insert(Balanced, tuning_from_curves(
        &[(45,5),(49,22),(54,38),(68,45),(74,56),(79,63),(84,81),(89,94)],
        &[(40,5),(42,20),(43,38),(60,43),(65,56),(69,66),(74,84),(78,112)],
    ));
    map.insert(Performance, tuning_from_curves(
        &[(20,28),(52,45),(57,63),(62,81),(67,94),(72,109),(81,147),(86,181)],
        &[(20,25),(39,43),(45,66),(50,84),(55,112),(60,127),(70,173),(76,201)],
    ));
    Tunings { profiles: map }   // adjust to real struct field name
}

fn dc_default_tunings() -> Tunings {
    use PlatformProfile::*;
    let mut map = HashMap::new();
    // DC × Quiet: same values as AC × Quiet
    map.insert(Quiet, tuning_from_curves(
        &[(60,5),(63,22),(66,38),(69,45),(72,56),(75,63),(78,81),(78,81)],
        &[(58,5),(60,20),(63,38),(65,43),(67,56),(70,66),(72,84),(72,84)],
    ));
    // DC × Balanced: PWM ceiling capped at 80% of AC (fans quieter on battery)
    map.insert(Balanced, tuning_from_curves(
        &[(45,4),(49,18),(54,30),(68,36),(74,45),(79,50),(84,65),(89,75)],
        &[(40,4),(42,16),(43,30),(60,34),(65,45),(69,53),(74,67),(78,90)],
    ));
    // DC × Performance: identical curve values to DC × Balanced
    map.insert(Performance, tuning_from_curves(
        &[(45,4),(49,18),(54,30),(68,36),(74,45),(79,50),(84,65),(89,75)],
        &[(40,4),(42,16),(43,30),(60,34),(65,45),(69,53),(74,67),(78,90)],
    ));
    Tunings { profiles: map }
}
```

Also add the helper:

```rust
fn tuning_from_curves(cpu: &[(u8, u8); 8], gpu: &[(u8, u8); 8]) -> Tuning {
    let mut group = HashMap::new();
    let (cpu_temp, cpu_pwm): (Vec<u8>, Vec<u8>) = cpu.iter().cloned().unzip();
    let (gpu_temp, gpu_pwm): (Vec<u8>, Vec<u8>) = gpu.iter().cloned().unzip();
    group.insert(Fan::CPU, CurveData {
        fan: Fan::CPU,
        temp: cpu_temp.try_into().unwrap(),
        pwm: cpu_pwm.try_into().unwrap(),
        enabled: false,
    });
    group.insert(Fan::GPU, CurveData {
        fan: Fan::GPU,
        temp: gpu_temp.try_into().unwrap(),
        pwm: gpu_pwm.try_into().unwrap(),
        enabled: false,
    });
    Tuning { enabled: false, group }
}
```

**Adjust field names** (`profiles`, `group`, `Fan::CPU`, etc.) to whatever Step 1 found in the fork's real code. If types don't match, add a small conversion helper.

Update `impl Default for Config`:

```rust
ac_profile_tunings: ac_default_tunings(),
dc_profile_tunings: dc_default_tunings(),
```

- [ ] **Step 3: Wire the tunings into the sysfs watcher**

Find the block inside `create_tasks` that ALREADY calls `apply_fan_curves_and_ppt(&attrs, power_plugged, profile).await` inside the logind-based `on_external_power_change` closure (roughly line 941 in the Phase-1-patched tree). Read its exact signature.

Then, inside the sysfs power watcher we added in Phase 1 (the `let platform_sysfs = self.clone(); tokio::spawn(async move { … })` block), after the kbd-brightness block from Task 2 and BEFORE the `last_power_plugged` assignment:

```rust
                // Fan curves per (profile × power source) — Phase 2a Task 3.
                // If the tuning cell is enabled, apply its curve; else the
                // profile default stays in effect.
                if let Ok(profile) = platform_sysfs.platform.get_platform_profile().map(|p| p.into()) {
                    let attrs = FirmwareAttributes::new();
                    platform_sysfs
                        .apply_fan_curves_and_ppt(&attrs, plugged, profile)
                        .await;
                }
```

Also modify `apply_fan_curves_and_ppt` itself to actually read the right tunings map based on `power_plugged`. Grep for its body:

```bash
grep -n "fn apply_fan_curves_and_ppt\|apply_fan_curves_and_ppt" /home/cyberpunk/asus/fork/asusctl/asusd/src/ctrl_platform.rs
```

Inside `apply_fan_curves_and_ppt`, find where it currently picks a Tuning (probably calls `self.config.lock().await.select_tunings(power_plugged, profile)`). If it doesn't yet: add a call to `select_tunings` that returns `&mut Tuning` for the (power × profile) cell, and if `tuning.enabled` is true, iterate `tuning.group` and call `write_profile_curve_to_platform` on each `CurveData` — otherwise leave the profile's stored curve in place.

The exact code depends on what Step 1 found. General shape:

```rust
async fn apply_fan_curves_and_ppt(
    &self,
    attrs: &FirmwareAttributes,
    power_plugged: bool,
    profile: PlatformProfile,
) {
    let tuning = self.config.lock().await.select_tunings(power_plugged, profile).clone();
    if !tuning.enabled {
        debug!("apply_fan_curves_and_ppt: tuning disabled for {:?} on {}", profile,
               if power_plugged { "AC" } else { "battery" });
        return;
    }
    for (fan, curve_data) in tuning.group.iter() {
        debug!("apply_fan_curves_and_ppt: writing {:?} curve for {:?}", fan, profile);
        // Call the same helper the existing profile-switch code uses:
        rog_profiles::write_profile_curve_to_platform(profile, curve_data.clone());
    }
}
```

Confirm the exact `rog_profiles::write_profile_curve_to_platform` signature by re-grepping if the compiler complains.

- [ ] **Step 4: Build the patched fork**

```bash
cd /home/cyberpunk/asus/fork/asusctl
git add asusd/src/config.rs asusd/src/ctrl_platform.rs
git commit -m "asusd: fan curves per (profile x power source) auto-apply

Populates ac_profile_tunings and dc_profile_tunings in Config::default()
with sensible curves for all six cells (Q/B/P x AC/DC). All cells
default to enabled: false — opt-in per project policy.

On AC/battery transition (via the Phase 1 sysfs watcher), asusd looks up
the (profile x power source) cell; if enabled, its curve is written to
hwmon PWM tables via rog_profiles::write_profile_curve_to_platform,
overriding the profile's default curve. Disabled cell = current behavior
preserved."
cd /home/cyberpunk/asus
./scripts/build-fork-asusctl.sh 2>&1 | tail -8
```

Expected: `3 patch(es) applied`, cargo `Finished release [optimized]`.

- [ ] **Step 5: Install and verify — AC+load Balanced**

```bash
echo <sudo password> | sudo -S bash /home/cyberpunk/asus/scripts/install-fork-asusd-test.sh 2>&1 | tail -6
export PATH=/usr/local/bin:/usr/local/sbin:$PATH
# Enable the AC×Balanced tuning cell only:
# Stop daemon, edit /etc/asusd/asusd.ron so ac_profile_tunings.Balanced.enabled = true, restart
sudo systemctl stop asusd-test.service
sudo sed -i 's|Balanced: (\s*enabled: false,\s*group: {|Balanced: (\n            enabled: true,\n            group: {|1' /etc/asusd/asusd.ron
sudo systemctl start asusd-test.service
sleep 2
# Set profile
asusctl profile set Balanced
sleep 1
# Load
stress-ng --cpu 8 --timeout 60s &
sleep 15
# Observe fan RPM under load
cat /sys/class/hwmon/hwmon5/fan1_input
cat /sys/class/hwmon/hwmon5/fan2_input
```

Expected: fan RPMs match the AC × Balanced curve (should track the default 6.3.8 Balanced curve at ~74°C hitting ~4000 RPM, per Phase 1 Task 9 observations).

- [ ] **Step 6: Verify AC → battery: fan curve changes**

Kill workload, unplug AC. Restart workload. Observe fan RPMs.

```bash
kill %1 2>/dev/null
sleep 3   # let it settle
stress-ng --cpu 8 --timeout 60s &
sleep 15
cat /sys/class/hwmon/hwmon5/fan1_input   # should be LOWER than AC (DC × Balanced has 20% lower ceiling)
cat /sys/class/hwmon/hwmon5/fan2_input
```

Only the AC×Balanced cell was enabled. DC×Balanced is still `enabled: false`, so on battery the daemon falls back to the profile's default curve — RPM should approximately match Phase 1 Task 9's batt+load observations.

**Then enable DC×Balanced too** and repeat:

```bash
sudo systemctl stop asusd-test.service
# Edit /etc/asusd/asusd.ron to set dc_profile_tunings.Balanced.enabled = true
sudo systemctl start asusd-test.service
kill %1 2>/dev/null
sleep 3
stress-ng --cpu 8 --timeout 60s &
sleep 15
cat /sys/class/hwmon/hwmon5/fan1_input   # should now match the DC × Balanced ceiling (~80% of AC)
```

- [ ] **Step 7: Verify opt-out — disable both cells, repeat load test, RPMs match Phase 1 Task 9's baseline**

- [ ] **Step 8: Record verification, teardown**

Write `docs/superpowers/verification/2026-07-03-phase2a-verify-task3.md`: table of (profile × power × tuning enabled/disabled × RPM ranges observed). Should show that enabling DC cells produces lower RPM ceilings vs disabling them.

```bash
sudo bash /home/cyberpunk/asus/scripts/phase1-teardown.sh
```

- [ ] **Step 9: Export patch + PR**

```bash
git -C /home/cyberpunk/asus/fork/asusctl format-patch fork/base..HEAD --start-number 3 -o /tmp/
mv /tmp/0003-*.patch /home/cyberpunk/asus/patches/asusctl/0003-fan-curve-per-ac-dc.patch
echo "0003-fan-curve-per-ac-dc.patch" >> /home/cyberpunk/asus/patches/asusctl/series
cd /home/cyberpunk/asus
git checkout -b phase2a/task3-fan-curve-per-ac-dc
git add patches/asusctl/series patches/asusctl/0003-fan-curve-per-ac-dc.patch docs/superpowers/verification/2026-07-03-phase2a-verify-task3.md
git commit -m "Phase 2a Task 3: fan curve per (profile x power source)"
git push -u origin phase2a/task3-fan-curve-per-ac-dc
gh pr create --title "Phase 2a Task 3: fan curve per (profile x power source)" \
    --body "Populates ac/dc_profile_tunings with sensible per-cell curves. All cells default enabled: false. Verified on FA507NV: enabling AC×Balanced produces the AC-side curve under load; enabling DC×Balanced with different values produces the DC-side curve on battery under load; both disabled preserves Phase 1 baseline behavior."
```

---

### Task 4: Patch — `gpu_mode_per_power`

**Files:**
- Modify: `fork/asusctl/asusd/src/config.rs` (three new fields + validation on load)
- Create: `fork/asusctl/asusd/src/supergfxd_client.rs` (new file, ≤ 150 lines)
- Create: `fork/asusctl/asusd/src/notification_client.rs` (new file, ≤ 100 lines)
- Modify: `fork/asusctl/asusd/src/lib.rs` (declare the two new modules)
- Modify: `fork/asusctl/asusd/src/ctrl_platform.rs` (call supergfxd + notification from sysfs watcher)
- Create: `docs/superpowers/verification/2026-07-03-phase2a-verify-task4.md`
- Export: `patches/asusctl/0004-gpu-mode-per-power.patch`
- (possibly) Export: `patches/supergfxctl/0002-*.patch`
- Modify: `patches/asusctl/series` (+ maybe `patches/supergfxctl/series`)

**Consumes:** Phase 1's `0001`, Task 2's `0002`, Task 3's `0003`. supergfxctl's `GfxMode` enum (asusd already vendors supergfxctl 5.2.7 as a git dep — no new dependency needed). Fork's own supergfxd running on this box (we'll install via `install-fork-supergfxd-test.sh`).

**Produces:** on AC/battery transition, if `change_gpu_mode_on_power: true`, asusd calls supergfxd's `SetMode` dbus method with the configured target for the new state. supergfxd stages the mode change (session-safe, logout to apply, Phase 0 verified). asusd fires a freedesktop notification if it can find a user session bus.

**Interfaces:**
- Consumes: `AsusPower::get_online()`, `Config::change_gpu_mode_on_power`, `supergfxctl::GfxMode`. supergfxd dbus at `org.supergfxctl.Daemon` (path and interface name confirmed by introspection at Step 1).
- Produces: three new config fields. New modules `supergfxd_client` (exports `SupergfxdClient::new()` and `set_mode(mode)`) and `notification_client` (exports `NotificationClient::try_notify(summary, body)`).

- [ ] **Step 1: Introspect the running supergfxd's dbus interface**

Install our fork's supergfxd for introspection:

```bash
echo <sudo password> | sudo -S bash /home/cyberpunk/asus/scripts/install-fork-supergfxd-test.sh 2>&1 | tail -3
gdbus introspect --system --dest org.supergfxctl.Daemon --object-path / --recurse 2>&1 | head -60
```

Record:
- Object path (probably `/org/supergfxctl/Daemon`)
- Interface name for gfx methods (probably `org.supergfxctl.Daemon`)
- The exact method name and signature — likely `SetMode(mode: String) -> String` or `SetMode(mode: u32) -> String`. **Record the actual signature.**

Also grep the supergfxctl source for hints:

```bash
grep -rn "#\[interface\|dbus_interface\|method\|SetMode" /home/cyberpunk/asus/fork/supergfxctl/src/ 2>/dev/null | head
```

- [ ] **Step 2: Create `fork/asusctl/asusd/src/supergfxd_client.rs`**

Skeleton (adapt method signatures to Step 1 introspection):

```rust
// Phase 2a Task 4: minimal zbus proxy to supergfxd for GPU-mode auto-switch.
//
// Runs from asusd's system-bus connection. Only used when
// change_gpu_mode_on_power = true and the sysfs power watcher fires.

use log::{debug, warn};
use zbus::proxy;

// If Step 1 found the interface at a different name, edit here:
#[proxy(
    interface = "org.supergfxctl.Daemon",
    default_service = "org.supergfxctl.Daemon",
    default_path = "/org/supergfxctl/Daemon"
)]
trait SupergfxDbus {
    // If SetMode takes u32: change signature to (u8 or u32) accordingly.
    // Return type: String is what supergfxctl -m prints ("Graphics mode changed to Integrated. Required user action is: Logout required...").
    async fn set_mode(&self, mode: &str) -> zbus::Result<String>;
}

pub struct SupergfxdClient {
    proxy: SupergfxDbusProxy<'static>,
}

impl SupergfxdClient {
    /// Connect on the *system* dbus (supergfxd is a system service).
    pub async fn new() -> Result<Self, zbus::Error> {
        let conn = zbus::Connection::system().await?;
        let proxy = SupergfxDbusProxy::new(&conn).await?;
        Ok(Self { proxy })
    }

    /// Queue a mode change. supergfxd handles staging (logout-required).
    /// Returns the supergfxd reply for logging.
    pub async fn set_mode(&self, mode: &str) -> Result<String, zbus::Error> {
        debug!("supergfxd_client: SetMode({mode})");
        let reply = self.proxy.set_mode(mode).await?;
        debug!("supergfxd_client: reply = {reply}");
        Ok(reply)
    }
}
```

If introspection at Step 1 revealed a different signature (e.g. `SetMode(u32)`), adjust the trait and helper.

- [ ] **Step 3: Create `fork/asusctl/asusd/src/notification_client.rs`**

freedesktop notifications live on the session bus. asusd runs on the system bus. To notify a user, we need to find the graphical session's bus and connect there. Use logind's `ListSessions` → `GetSession` → session's `Class == "user" && Active == true` → get `Name` (username) → construct `unix:path=/run/user/<uid>/bus`.

Skeleton — this is a best-effort helper. If no user session is reachable, we log and continue. Never propagate an error out of a notification call — the mode change is what matters.

```rust
// Phase 2a Task 4: best-effort freedesktop notification helper.
//
// asusd runs on system bus. Notifications live on session bus. We look
// up an active graphical session via logind and connect to that user's
// session bus. Any failure is logged and swallowed — the primary
// operation (GPU mode change) must not fail because a notification
// can't be delivered.

use log::{debug, warn};
use std::collections::HashMap;
use zbus::{proxy, Connection};

#[proxy(
    interface = "org.freedesktop.login1.Manager",
    default_service = "org.freedesktop.login1",
    default_path = "/org/freedesktop/login1"
)]
trait LogindManager {
    async fn list_sessions(&self) -> zbus::Result<Vec<(String, u32, String, String, zbus::zvariant::OwnedObjectPath)>>;
}

#[proxy(
    interface = "org.freedesktop.login1.Session",
    default_service = "org.freedesktop.login1"
)]
trait LogindSession {
    #[zbus(property)]
    async fn active(&self) -> zbus::Result<bool>;
    #[zbus(property)]
    async fn user(&self) -> zbus::Result<(u32, zbus::zvariant::OwnedObjectPath)>;
    #[zbus(property)]
    async fn class(&self) -> zbus::Result<String>;
}

#[proxy(
    interface = "org.freedesktop.Notifications",
    default_service = "org.freedesktop.Notifications",
    default_path = "/org/freedesktop/Notifications"
)]
trait Notifications {
    #[allow(clippy::too_many_arguments)]
    async fn notify(
        &self,
        app_name: &str,
        replaces_id: u32,
        app_icon: &str,
        summary: &str,
        body: &str,
        actions: Vec<&str>,
        hints: HashMap<&str, zbus::zvariant::Value<'_>>,
        expire_timeout: i32,
    ) -> zbus::Result<u32>;
}

pub struct NotificationClient;

impl NotificationClient {
    pub async fn try_notify(summary: &str, body: &str) {
        if let Err(e) = Self::inner(summary, body).await {
            debug!("notification_client: try_notify swallow: {e}");
        }
    }

    async fn inner(summary: &str, body: &str) -> Result<(), zbus::Error> {
        let sys = Connection::system().await?;
        let logind = LogindManagerProxy::new(&sys).await?;
        let sessions = logind.list_sessions().await?;

        for (_sid, uid, _uname, _seat, path) in sessions {
            let sess = LogindSessionProxy::builder(&sys).path(path)?.build().await?;
            if !sess.active().await.unwrap_or(false) { continue; }
            if sess.class().await.unwrap_or_default() != "user" { continue; }
            let bus_path = format!("unix:path=/run/user/{uid}/bus");
            debug!("notification_client: trying session bus {bus_path}");
            let session_conn =
                Connection::address(bus_path.as_str())?.build().await?;
            let notif = NotificationsProxy::new(&session_conn).await?;
            notif.notify(
                "asusctl", 0, "input-keyboard",
                summary, body,
                vec![], HashMap::new(), 5000,
            ).await?;
            return Ok(());
        }
        Err(zbus::Error::Failure("no active user session for notification".to_string()))
    }
}
```

If `Connection::address(...).build()` API is different in the zbus version in-tree, grep for the actual constructor:

```bash
grep -rn "Connection::address\|ConnectionBuilder" /home/cyberpunk/asus/fork/asusctl/*/src/ 2>/dev/null | head
```

Adapt accordingly.

- [ ] **Step 4: Register modules in `fork/asusctl/asusd/src/lib.rs`**

Locate the module declarations near the top of lib.rs. Add:

```rust
mod supergfxd_client;
mod notification_client;
```

- [ ] **Step 5: Add three config fields to `Config` in `config.rs`**

```rust
    // GPU mode auto-switch on AC/battery — Phase 2a Task 4. Opt-in.
    // AsusMuxDgpu is REJECTED as a valid value at config load; if
    // encountered, it's downgraded to Hybrid with a warn!.
    #[serde(default = "default_gpu_mode_on_ac")]
    pub gpu_mode_on_ac: GfxMode,
    #[serde(default = "default_gpu_mode_on_battery")]
    pub gpu_mode_on_battery: GfxMode,
    #[serde(default)]
    pub change_gpu_mode_on_power: bool,
```

Helpers below `impl Default for Config`:

```rust
fn default_gpu_mode_on_ac() -> GfxMode { GfxMode::Hybrid }
fn default_gpu_mode_on_battery() -> GfxMode { GfxMode::Integrated }

pub fn sanitize_gpu_mode(m: GfxMode, field: &str) -> GfxMode {
    if matches!(m, GfxMode::AsusMuxDgpu) {
        warn!("Config: {field} = AsusMuxDgpu is not allowed for auto-switch \
               (reboot required). Downgrading to Hybrid.");
        GfxMode::Hybrid
    } else {
        m
    }
}
```

Add `use supergfxctl::special::GfxMode;` (adjust path — grep for `enum GfxMode` in supergfxctl fork if uncertain).

Update `impl Default for Config`:

```rust
gpu_mode_on_ac: GfxMode::Hybrid,
gpu_mode_on_battery: GfxMode::Integrated,
change_gpu_mode_on_power: false,
```

Add a post-load sanitize call — wherever `Config` is loaded from disk (grep `pub fn load\|pub fn read`), immediately after deserialize:

```rust
cfg.gpu_mode_on_ac = sanitize_gpu_mode(cfg.gpu_mode_on_ac, "gpu_mode_on_ac");
cfg.gpu_mode_on_battery = sanitize_gpu_mode(cfg.gpu_mode_on_battery, "gpu_mode_on_battery");
```

- [ ] **Step 6: Wire the trigger into the sysfs power watcher in `ctrl_platform.rs`**

At the top of the file add the imports:

```rust
use crate::supergfxd_client::SupergfxdClient;
use crate::notification_client::NotificationClient;
```

In `create_tasks`, BEFORE the sysfs `tokio::spawn` block: build a shared `SupergfxdClient` once and clone into the spawn:

```rust
        // GPU mode auto-switch — Phase 2a Task 4. Shared client, connected once.
        let supergfxd = match SupergfxdClient::new().await {
            Ok(c) => Some(std::sync::Arc::new(c)),
            Err(e) => {
                warn!("supergfxd_client: could not connect: {e}. gpu-mode auto-switch disabled at runtime.");
                None
            }
        };
```

Inside the `tokio::spawn(async move { … })` block, clone `supergfxd`:

```rust
        let supergfxd = supergfxd.clone();
```

Inside the "state changed" if-block, AFTER the fan-curve block from Task 3 and BEFORE the `last_power_plugged` assignment:

```rust
                // GPU mode auto-switch — Phase 2a Task 4.
                {
                    let cfg = platform_sysfs.config.lock().await;
                    if cfg.change_gpu_mode_on_power {
                        if let Some(sg) = &supergfxd {
                            let target = if plugged {
                                cfg.gpu_mode_on_ac
                            } else {
                                cfg.gpu_mode_on_battery
                            };
                            // GfxMode -> string form supergfxd's SetMode expects:
                            let target_str = match target {
                                GfxMode::Integrated => "Integrated",
                                GfxMode::Hybrid => "Hybrid",
                                GfxMode::AsusMuxDgpu => {
                                    warn!("gpu_mode auto: AsusMuxDgpu suppressed at runtime");
                                    return; // skip the mode change; keep watcher alive via macro exit
                                }
                            };
                            drop(cfg); // release lock before await
                            match sg.set_mode(target_str).await {
                                Ok(reply) => {
                                    debug!("sysfs power watcher: gpu-mode queued -> {target_str} ({reply})");
                                    let summary = "asusctl: GPU mode change queued";
                                    let body = format!(
                                        "Target: {target_str}. Log out to apply.\n(supergfxd said: {reply})"
                                    );
                                    NotificationClient::try_notify(summary, &body).await;
                                }
                                Err(e) => {
                                    warn!("sysfs power watcher: supergfxd SetMode failed: {e}");
                                }
                            }
                        }
                    }
                }
```

Note the `return;` for AsusMuxDgpu is inside a block — replace with a labeled break or restructure to `continue` back to the outer loop instead. Concrete rewrite:

```rust
                let gpu_target: Option<&'static str> = {
                    let cfg = platform_sysfs.config.lock().await;
                    if cfg.change_gpu_mode_on_power {
                        let m = if plugged { cfg.gpu_mode_on_ac } else { cfg.gpu_mode_on_battery };
                        match m {
                            GfxMode::Integrated => Some("Integrated"),
                            GfxMode::Hybrid     => Some("Hybrid"),
                            GfxMode::AsusMuxDgpu => {
                                warn!("gpu_mode auto: AsusMuxDgpu suppressed at runtime");
                                None
                            }
                        }
                    } else { None }
                };
                if let (Some(target_str), Some(sg)) = (gpu_target, supergfxd.as_ref()) {
                    match sg.set_mode(target_str).await {
                        Ok(reply) => {
                            debug!("sysfs power watcher: gpu-mode queued -> {target_str} ({reply})");
                            let body = format!("Target: {target_str}. Log out to apply.");
                            NotificationClient::try_notify(
                                "asusctl: GPU mode change queued",
                                &body,
                            ).await;
                        }
                        Err(e) => {
                            warn!("sysfs power watcher: supergfxd SetMode failed: {e}");
                        }
                    }
                }
```

- [ ] **Step 7: Build the patched fork**

```bash
cd /home/cyberpunk/asus/fork/asusctl
git add asusd/src/config.rs asusd/src/ctrl_platform.rs asusd/src/lib.rs \
        asusd/src/supergfxd_client.rs asusd/src/notification_client.rs
git commit -m "asusd: GPU mode auto-switch on AC/battery via supergfxd dbus

Adds change_gpu_mode_on_power (opt-in), gpu_mode_on_ac (default Hybrid),
gpu_mode_on_battery (default Integrated). AsusMuxDgpu is rejected at
config-load and again at runtime — reboot-required, hostile UX for an
automatic action.

New modules:
- asusd/src/supergfxd_client.rs — zbus proxy for
  org.supergfxctl.Daemon.SetMode, connects on system bus at daemon start.
- asusd/src/notification_client.rs — best-effort freedesktop notification
  helper. Finds an active user session via logind, connects to that
  user's session bus, fires a notification. Failures are logged and
  swallowed; the mode change must not fail because a notification can't
  be delivered.

Wired into the Phase 1 sysfs power watcher — same event source, same
2-second polling, same idempotency semantics. Logout-required semantics
inherited from supergfxd (Phase 0 verified session-safe on FA507NV)."
cd /home/cyberpunk/asus
./scripts/build-fork-asusctl.sh 2>&1 | tail -12
```

Expected: `4 patch(es) applied` (or `5` if a supergfxctl patch was needed), cargo `Finished release [optimized]`.

If a `SetMode` method wasn't exposed on supergfxd and we needed to patch it: also do a `format-patch` + append to `patches/supergfxctl/series` first, then rebuild.

- [ ] **Step 8: Install + verify on FA507NV — baseline**

```bash
# supergfxd should already be installed from Step 1
echo <sudo password> | sudo -S bash /home/cyberpunk/asus/scripts/install-fork-asusd-test.sh 2>&1 | tail -3
export PATH=/usr/local/bin:/usr/local/sbin:$PATH
supergfxctl -g   # expect Hybrid
# Enable the automation, keep default targets
sudo systemctl stop asusd-test.service
# In /etc/asusd/asusd.ron: set change_gpu_mode_on_power: true
sudo systemctl start asusd-test.service
sleep 3
# Confirm the SupergfxdClient connected
sudo journalctl -u asusd-test.service --no-pager -n 20 | grep supergfxd_client
```

Expected: no "could not connect" warning.

- [ ] **Step 9: Verify AC → battery: mode change queued to Integrated**

Unplug AC. Within ~5 seconds:

```bash
sudo journalctl -u asusd-test.service --no-pager -n 15 | grep -E "gpu-mode|supergfxd_client"
supergfxctl -g                # live mode unchanged (still Hybrid)
supergfxctl --status | head   # pending action = "Logout required..."
```

If a desktop notification popup appeared: record it. If not: check the journal for `notification_client: try_notify swallow: …` — a swallowed error is expected on some systems.

- [ ] **Step 10: Cancel the pending mode change (per Phase 0 semantics)**

```bash
supergfxctl -m Hybrid
sleep 2
supergfxctl --status | head   # pending cleared
```

Do NOT log out. This proves the automation queues but user is in control of the actual switch.

- [ ] **Step 11: Verify battery → AC: mode change queued to Hybrid**

Plug AC. Repeat the same journal + supergfxctl commands as Step 9. Cancel via `supergfxctl -m Hybrid` again (target and current match — no-op cancel).

- [ ] **Step 12: Verify AsusMuxDgpu suppression**

Stop daemon. In `/etc/asusd/asusd.ron`, set `gpu_mode_on_ac: AsusMuxDgpu`. Start daemon.

```bash
sudo journalctl -u asusd-test.service --no-pager -n 20 | grep -i asusmux
# Expected: "Config: gpu_mode_on_ac = AsusMuxDgpu is not allowed for auto-switch (reboot required). Downgrading to Hybrid."
```

Then plug/unplug AC to trigger the watcher. Expected: `warn!("gpu_mode auto: AsusMuxDgpu suppressed at runtime")` — the runtime check as belt-and-suspenders.

- [ ] **Step 13: Verify opt-out — set `change_gpu_mode_on_power: false`, restart daemon, transition AC, no journal about gpu-mode**

- [ ] **Step 14: Record verification, teardown**

Write `docs/superpowers/verification/2026-07-03-phase2a-verify-task4.md`: full sequence of journal grep + supergfxctl status output for each verify sub-step. Include the notification-attempt outcome (delivered or swallowed).

```bash
sudo bash /home/cyberpunk/asus/scripts/phase1-teardown.sh
```

- [ ] **Step 15: Export patch + PR**

```bash
git -C /home/cyberpunk/asus/fork/asusctl format-patch fork/base..HEAD --start-number 4 -o /tmp/
mv /tmp/0004-*.patch /home/cyberpunk/asus/patches/asusctl/0004-gpu-mode-per-power.patch
echo "0004-gpu-mode-per-power.patch" >> /home/cyberpunk/asus/patches/asusctl/series
# If a supergfxctl patch was added in Step 7:
#   git -C /home/cyberpunk/asus/fork/supergfxctl format-patch fork/base..HEAD --start-number 2 -o /tmp/
#   mv /tmp/0002-*.patch /home/cyberpunk/asus/patches/supergfxctl/0002-expose-setmode-dbus.patch
#   echo "0002-expose-setmode-dbus.patch" >> /home/cyberpunk/asus/patches/supergfxctl/series
cd /home/cyberpunk/asus
git checkout -b phase2a/task4-gpu-mode-per-power
git add patches/ docs/superpowers/verification/2026-07-03-phase2a-verify-task4.md
git commit -m "Phase 2a Task 4: GPU mode auto-switch on AC/battery"
git push -u origin phase2a/task4-gpu-mode-per-power
gh pr create --title "Phase 2a Task 4: GPU mode auto-switch on AC/battery" \
    --body "asusd -> supergfxd dbus SetMode from the sysfs power watcher on transitions. Opt-in default. AsusMuxDgpu rejected at config-load and again at runtime. Session-safe: supergfxd queues the switch with the standard logout-required semantics (Phase 0 verified). Notifications are best-effort via a user-session bus lookup — swallowed on failure so the mode change is never blocked."
```

---

## Phase 2a completion criteria

- All 4 task PRs merged by user (each preceded by its own verification report on FA507NV)
- `patches/asusctl/series` reads: 0001 → 0002 → 0003 → 0004
- `./scripts/build-fork-asusctl.sh` applies all four patches cleanly from a fresh clone and cargo `Finished release [optimized]`
- Feature catalog is on main, referenced by patches 0002-0004
- FA507NV state matches pre-Phase-2a snapshot (`/tmp/asus-phase2a-snapshot/`)
- Tag `phase2a-v0.1-patches` applied to main after all merges

Tag command (user-only step — do NOT run without explicit user approval):

```bash
git checkout main && git pull
git tag -a phase2a-v0.1-patches -m "Phase 2a: kbd brightness, fan curve per AC/DC, GPU mode per power auto-switch. Opt-in defaults."
git push origin phase2a-v0.1-patches
```

Once tagged, Phase 2b (Debian packaging + PPA + CI + user docs) plan is written against this frozen patch series.
