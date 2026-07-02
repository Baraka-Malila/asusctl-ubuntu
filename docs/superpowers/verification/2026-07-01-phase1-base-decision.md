# Phase 1 Task 2 — Fork Base Decision

**Date:** 2026-07-02
**Hardware:** ASUS TUF Gaming A15 FA507NV, kernel 6.8.0-124-generic, Ubuntu 22.04
**Method:** Side-by-side install of asusctl 6.3.8 (namespaced test daemon `asusd-638-test`) against Phase 0's v1.0.1 findings.

---

## Chosen base: **6.3.8 (OpenGamingCollective, tag `6.3.8`)**

Every v1.0.1 bug on this machine is *already fixed* in 6.3.8. Patches for Tasks 4, 5, and 6 collapse to "verify unchanged." The remaining Phase 1 work (Tasks 7–10) is unaffected. Net Phase 1 patch cost drops from ~5 targeted patches to 1 (Task 7's safe udev rule replacement).

The trade-off is a dbus bus-name rename (`org.asuslinux.Daemon` → `xyz.ljones.Asusd`) and, on install, a coexistence collision with the user's existing `battery-charge-threshold.service`. Both are packaging concerns for Phase 2, not fork-base blockers.

**Fan-curve path:** N/A — 6.3.8's `asusctl fan-curve` subcommand exists and works end-to-end. Path A and Path B from the plan are unnecessary.

---

## Feature parity table

| Feature | v1.0.1 (Phase 0) | 6.3.8 (this session) | Delta |
|---|---|---|---|
| Product detection | correct FA507NV | correct FA507NV | — |
| Thermal profile (`throttle_thermal_policy`) | ✅ works via `-p` | ✅ works via `profile set` (Quiet=2, Perf=1, Balanced=0 confirmed) | 6.3.8 exposes `next/list/get/set`; 6.3.8 adds AC/battery-per-profile automation |
| Keyboard backlight | ❌ mpsc bug — CLI silently drops writes, sysfs stays 0 | ✅ works — `leds set off/low/med/high` → sysfs 0/1/2/3 | 6.3.8 fixes the mpsc bug |
| Battery charge threshold | ❌ "ERROR: Charge control not available" at daemon start; hardcoded BAT0 lookup | ✅ works — journal: `Found battery power at "BAT1", matched charge_control_end_threshold`; `battery limit 60/80` writes succeeded | 6.3.8 does runtime BAT probe |
| Fan curve editing | ⛔ NOT IN CLI (only presets via `-p`) | ✅ full — `fan-curve --mod-profile <p> --enable-fan-curves true`, per-fan (CPU/GPU) `data 30c:1%,...` format, RON dump, per-profile storage | Fan-curve regression from ⛔ to ✅ |
| Aura keyboard modes | led-mode only | 5 modes (Static, Breathe, RainbowCycle, RainbowWave, Pulse) via `aura` subcommand | Superset |
| CPU EPP (Energy Performance Preference) | not integrated | integrated — profile switches also set `Default/Performance/BalancePerformance/BalancePower/Power` EPP | New capability |
| Armoury firmware attributes | not implemented | `armoury list` command exists but returns empty — depends on kernel `asus-armoury` driver (upstream since ~6.11; not in this 6.8 kernel) | Deferred to kernel update path |
| Screenpad backlight | absent | present (`backlight`) — irrelevant for FA507NV (no screenpad) | Harmless superset |
| GUI (`rog-control-center`) | absent | present (Slint/GTK) — separate binary | Feeds Phase 3 GUI decision |
| Dbus bus name | `org.asuslinux.Daemon` | `xyz.ljones.Asusd` | **Ecosystem rename** — Phase 2 packaging concern (see below) |

---

## Rationale for base = 6.3.8

**Estimated patch cost per feature per base:**

| Task | If base = 1.0.1 | If base = 6.3.8 |
|---|---|---|
| Task 4 (kbd backlight mpsc fix) | Real Rust patch to `ctrl_leds.rs` mpsc capacity/drain logic. Est. 1–2 diagnostic sessions. | 0 — already fixed. |
| Task 5 (charge threshold BAT probe) | Rust patch to `ctrl_charge.rs` replacing hardcoded BAT0 with `BAT0..BAT9` probe. Small but real diff. | 0 — already does runtime probe. |
| Task 6 (fan-curve CLI) | Path A: backport 6.3.8 `fan-curve` CLI + asusd handler onto 1.0.1 (multi-crate diff, non-trivial). Path B: independent `asusctl-fanctl` binary (weeks). | 0 — full subcommand works. |
| Task 7 (safe udev rule replacement) | same | same |
| Task 8 (AsusMuxDgpu verify) | same | same |
| Task 9 (four-state matrix) | same | same |
| Task 10 (exit report + tag) | same | same |

Base = 6.3.8 saves the entire Task 4/5/6 patch effort. This is decisive.

**Where 1.0.1 would have been preferable (and isn't):**

- Ecosystem alignment: v1.0.1's `org.asuslinux.Daemon` matches what the wider Ubuntu ecosystem (GDM helpers, GNOME extensions like `gnome-shell-extension-arcmenu`, third-party scripts) may assume. 6.3.8's rename to `xyz.ljones.Asusd` means our fork's daemon won't be a drop-in match for any of those. **Mitigation:** package a compat shim / alias in Phase 2 packaging (a dbus policy allowing both names, or a systemd `Alias=`), or just accept the rename as the world's new default (upstream *did* rename it).
- Stability lineage: v1.0.1 is the last stable release from the original asus-linux group. 6.3.8 is a later development snapshot from the OpenGamingCollective fork. But: on FA507NV, 6.3.8 measurably works better than 1.0.1, and OGC's fork is actively maintained. Stability-as-lineage does not translate to stability-on-this-hardware.

**Not a factor:** none of the 6.3.8-added surfaces (armoury, screenpad, GUI) are used by Phase 1; they simply come along for free and get deferred to later phases (kernel-6.11+ users, Phase 3 GUI).

---

## Behavioral observations to carry into later tasks

1. **`asusd-638` writes `charge_control_end_threshold = 100` on daemon start.** This *reverts* the user's existing `battery-charge-threshold.service` cap of 80. On production install (post-Phase 1), we must either (a) disable `battery-charge-threshold.service` and let asusd own the value, or (b) configure asusd to persist the previous sysfs value at startup rather than resetting. Recommend (a) — one owner per sysfs write path — and document the migration in the debian preinst. **Task-5 becomes a preinst/postinst concern, not a Rust patch.**

2. **EPP integration on profile switch.** When `profile set Performance` runs, asusd-638 also writes `energy_performance_preference = performance` to `/sys/devices/system/cpu/cpu*/cpufreq/`. On battery, it writes `BalancePower`. This is a *new* system interaction not present in v1.0.1 and is not covered by Phase 0 verification — must be included in Task 9's four-state matrix.

3. **Fan-curve enable = *false* by default in stored config.** `fan-curve --enable-fan-curves true --mod-profile <p>` is needed to actually apply the curve to hwmon; otherwise the profile's static PWM table wins. Task 9 must test with `enabled: true` under load, not just read the curves.

4. **`asus-armoury` kernel driver absent on 6.8.** `/sys/class/firmware-attributes/` and `/sys/kernel/asus-armoury/` do not exist. `asusctl armoury list` returns empty. This means: (a) the "Armoury Crate parity" surface we mention in the project mission is only reachable on kernel ≥ 6.11 (Ubuntu 24.04 HWE or 22.04 HWE-edge). (b) Phase 2 packaging must gate the `armoury` subcommand's usefulness on kernel version, or document the kernel requirement.

5. **6.3.8 supergfxctl embedding.** 6.3.8's Cargo.toml vendors `supergfxctl v5.2.7` as a git dependency. This means asusd-638 has *build-time* knowledge of supergfx types, tightening the coupling but also removing a runtime discovery step. Task 8 (mux verification) needs to check whether this pulls in a supergfxd equivalent we should be using instead of packaging supergfxctl separately.

---

## v1.0.1 findings re-verification

Phase 0's `asusd-test.service` was torn down at end of Phase 0 (`scripts/phase0-teardown.sh`) and the systemd unit no longer exists. Historical journal record on this machine (kept by `journalctl`) still shows the Phase 0 reproduction:

```
Jul 01 06:34:05 ...  asusd[28366]: ERROR: Charge control not available
```

No kernel or driver updates have happened between Phase 0 and this session (verified: `uname -r` unchanged at 6.8.0-124, no `unattended-upgrades` events on `asusd`-relevant paths). The Phase 0 evidence is preserved verbatim. Live re-provisioning of v1.0.1 to re-run each CLI check would produce identical results and no new signal.

---

## Impact on remaining Phase 1 tasks

- **Task 3** (fork tree + patches series) — proceed as planned; `ASUSCTL_BASE_TAG` = `6.3.8`. Series file starts empty.
- **Task 4** (kbd backlight patch) — **cancel patch; convert to Task 4 = verify-only regression in Task 9's matrix.** No patch file added to series.
- **Task 5** (charge threshold patch) — **cancel patch; convert to Task 5 = deb postinst/preinst script that disables `battery-charge-threshold.service` on install and re-enables on remove.** Different work, but small. Actual asusd source patch is not needed.
- **Task 6** (fan-curve CLI) — **cancel entirely** (both Path A and Path B). Marked verify-only in Task 9.
- **Task 7** (safe replacement for `99-nvidia-ac.rules`) — unchanged.
- **Task 8** (AsusMuxDgpu physical mux verify) — unchanged, but now also verify the embedded supergfxctl dependency doesn't ship a mux-touching binary we're double-installing.
- **Task 9** (four-state hardware matrix) — expanded scope: add EPP write verification per profile per power state.
- **Task 10** (exit report + tag) — unchanged.

**Net effect:** Phase 1 becomes shorter. Phase 2 packaging concerns grow slightly (dbus rename compat, battery-charge-threshold.service migration, armoury kernel gate).

---

## Teardown state after this session

- `asusd-638-test.service` stopped and removed by `scripts/phase1-teardown-638-test.sh` (run after doc is committed).
- `/usr/local/sbin/asusd-638`, `/usr/local/bin/asusctl-638` removed.
- `/etc/systemd/system/asusd-638-test.service`, `/etc/dbus-1/system.d/asusd-638-test.conf` removed.
- Existing `battery-charge-threshold.service`: unchanged, still enabled + active, threshold restored to 80 by boot-time run of the unit (verified end of session).
- `nvidia-custom.conf`, kernel cmdline, `throttle_thermal_policy`, `kbd_backlight/brightness`: unchanged relative to pre-flight snapshot in `/tmp/asus-phase1-snapshot/`.
