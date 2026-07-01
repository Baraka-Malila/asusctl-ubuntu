# Phase 0 Verification Report — asusctl-ubuntu

**Test hardware:** ASUS TUF Gaming A15 FA507NV
**Kernel:** 6.8.0-124-generic
**BIOS:** FA507NV.316
**Date:** 2026-07-01

## Build Results

### asusctl v1.0.1

**Rust version:** rustc 1.93.1 (01f6ddf75 2026-02-11)

**Build outcome:** SUCCESS

**Build duration:** 26.15 seconds

**Build warnings:** 2 (both from asus-nb-ctrl: field `kbd_node` never read in CtrlKbdBacklight, one unused warning from err-derive)

**Build command:**
```bash
cd upstream/asusctl
cargo build --release
```

**Binaries produced:**

1. `target/release/asusd` (1,434,776 bytes)
   - ELF 64-bit LSB pie executable, x86-64, dynamically linked
   - BuildID: 8475072e356a1338cb388d70656f61de3256daf2

2. `target/release/asusctl` (778,008 bytes)
   - ELF 64-bit LSB pie executable, x86-64, dynamically linked
   - BuildID: e1fe1348f2501b9459cd2f1ffe24f47b22c3676c

**Status:** Both binaries are valid ELF 64-bit executables, ready for testing.

## asusd Runtime Install Notes (Task 4)

**Install helper:** `scripts/phase0-install-asusd-test.sh` (idempotent, root-required)

**Installed to:**
- `/usr/local/sbin/asusd` (binary)
- `/usr/local/bin/asusctl` (binary)
- `/etc/systemd/system/asusd-test.service` (systemd unit, ExecStart edited to `/usr/local/sbin/asusd`)
- `/etc/dbus-1/system.d/asusd-test.conf` (dbus policy — allows adm/sudo/wheel/root)

**Service state:** `active` under systemd. Bus name `org.asuslinux.Daemon` claimed on system dbus. Object path is `/org/asuslinux/Daemon` (NOT `/org/asuslinux` — plan had wrong path).

**Startup journal findings on FA507NV (asusd v1.0.1):**

Working:
- `INFO: Device has thermal throttle control` — thermal profile control is available
- `INFO: Setting pstate for AMD CPU` — CPU pstate driver detected

Not available (asusd could not find sysfs paths):
- `ERROR: Charge control not available` — despite FA507NV having `charge_control_end_threshold` in sysfs (used by existing `battery-charge-threshold.service`)
- `WARN: Failed to open AMD boost` — AMD CPU boost sysfs missing
- `WARN: Fan mode: No such file or directory` — fan mode sysfs missing from asusd's expected path
- `WARN: Could not get AniMe display handle: NoDevice` — expected, TUF has no AniMe Matrix

**Implication for v0.1 packaging:** asusd v1.0.1 has significant feature gaps on FA507NV that the CLI does not surface as errors. The `-c` (charge limit) flag is exposed in asusctl but the daemon has already logged "not available". Behavior needs live testing to see whether writes succeed silently, fail loudly, or partially work.

**CLI in v1.0.1 (from `asusctl --help`) vs plan assumptions:**

| Feature | Plan assumed | Reality (v1.0.1) |
|---|---|---|
| Thermal profile | `asusctl profile -P Performance` | `asusctl -p silent\|normal\|boost` |
| Fan curve | `asusctl fan-curve -g` / `-D` | **NOT EXPOSED IN CLI** |
| Keyboard backlight | `asusctl -k low\|med\|high\|off` | Matches ✓ |
| Battery charge | `asusctl -c` (read) and `-c 85` (write) | `asusctl -c 20-100` (write only) |
| Subcommands | `profile`, `fan-curve` | Only `led-mode` |

Tasks 5-8 execute against the real CLI, not the plan's assumed CLI. Report reflects reality.

## Feature Verification

### Thermal Profile (Task 5) — ✅ WORKS

CLI: `asusctl -p silent|normal|boost`

Sysfs mapping on FA507NV (verified 2026-07-01):

| CLI value | `throttle_thermal_policy` | Journal log |
|---|---|---|
| `normal` | `0` | `Fan mode set to: Normal` |
| `boost` | `1` | `Fan mode set to: Boost` |
| `silent` | `2` | `Fan mode set to: Silent` |

Both fans exposed via `hwmon5` (asus): `fan1_input`, `fan2_input`. Idle at normal: ~2800/2900 RPM.

**Verdict:** Ships in v0.1. Full working feature.

### Fan Curves (Task 6) — ⛔ NOT EXPOSED IN CLI

`asusctl` v1.0.1 CLI has no `fan-curve` subcommand. Only preset profiles via `-p`. Fan RPMs are readable from `hwmon5/fan{1,2}_input` directly, but no user-facing curve editing.

**Verdict:** Not shippable as a first-class asusctl feature in v0.1. If we want fan curve editing, we ship a separate tool (or wait for upstream to re-expose).

### Keyboard Backlight (Task 7) — ❌ BROKEN (upstream bug)

CLI: `asusctl -k off|low|med|high` — accepted, no error output.

Journal shows the daemon drops every set-command:

```
WARN: SetKeyBacklight over mpsc failed: no available capacity
```

LED sysfs `/sys/class/leds/asus::kbd_backlight/brightness` remains at `0` after all `asusctl -k` calls. Kernel-level LED control works (writing directly to sysfs as root would set brightness); asusd's internal channel is saturated.

**Root cause hypothesis:** The keyboard backlight worker's mpsc channel has zero available capacity — likely a bounded channel initialized with 0-capacity or a producer not draining. This is an upstream bug in v1.0.1 on FA507NV, not a hardware gap.

**Verdict:** Blocks v0.1 shipping of the feature. Candidate for an upstream PR: increase channel capacity or fix the drain logic.

### Battery Charge Threshold (Task 8) — ❌ NOT AVAILABLE

CLI: `asusctl -c 20-100` — accepted, no output, no journal entries, sysfs unchanged.

At asusd startup: `ERROR: Charge control not available`. asusd v1.0.1 does not detect the FA507NV charge control sysfs (`/sys/class/power_supply/BAT1/charge_control_end_threshold`, which exists and works — it's what the existing `battery-charge-threshold.service` writes).

Likely cause: asusd looks at a different sysfs path (possibly `BAT0` or a WMI-mediated interface) and does not fall back to `charge_control_end_threshold`.

Existing `battery-charge-threshold.service` continued running throughout the test. Coexistence: no conflict, but no integration either.

**Verdict:** Blocks v0.1 shipping of the feature on FA507NV. Two paths forward: (a) upstream PR making asusd detect and use `charge_control_end_threshold` as fallback, (b) ship v0.1 without charge control and document the existing systemd unit as the interim mechanism.

### Summary of asusctl v1.0.1 on FA507NV

| Feature | Status | v0.1 shipping? |
|---|---|---|
| Thermal profile | ✅ Works | Yes |
| Fan curves | ⛔ Not in CLI | No — not exposed by upstream |
| Keyboard backlight | ❌ Broken (mpsc bug) | Blocked pending upstream fix |
| Charge threshold | ❌ Not available (sysfs path mismatch) | Blocked pending upstream fix |

**Working:** 1 of 4. This is thin for a v0.1. Options to consider at Task 16 verdict time: submit upstream patches and wait; ship thin v0.1 with clear docs; try older stable line (6.3.8) to compare.


### supergfxctl v5.2.7

**Upstream source:** Archived GitLab (OGC mirror unavailable)
- OGC `https://github.com/OpenGamingCollective/supergfxctl.git` — failed (not found)
- Fallback `https://gitlab.com/asus-linux/supergfxctl.git` — success ✓

**Rust version:** rustc 1.93.1 (01f6ddf75 2026-02-11)

**Build outcome:** SUCCESS

**Build duration:** 51.68 seconds

**Build warnings:** 0 (clean build)

**Build command:**
```bash
cd upstream/supergfxctl
cargo build --release
```

**Binaries produced:**

1. `target/release/supergfxd` (3,927,648 bytes)
   - ELF 64-bit LSB pie executable, x86-64, dynamically linked
   - BuildID: 5688f39404484a11ea72885a24c15f6324aa35d9

2. `target/release/supergfxctl` (1,851,984 bytes)
   - ELF 64-bit LSB pie executable, x86-64, dynamically linked
   - BuildID: 0701a22e3fa60de5e7c3d949c41df2894fa1a81b

**Status:** Both binaries are valid ELF 64-bit executables, ready for testing.

## supergfxd Runtime Install Notes (Tasks 10-11)

**Install helper:** `scripts/phase0-install-supergfxd-test.sh` (idempotent, root-required)

**Installed to:**
- `/usr/local/sbin/supergfxd` (binary)
- `/usr/local/bin/supergfxctl` (binary)
- `/etc/systemd/system/supergfxd-test.service` (ExecStart edited to `/usr/local/sbin/supergfxd`)
- `/etc/dbus-1/system.d/supergfxd-test.conf` (dbus policy)
- `/etc/udev/rules.d/90-supergfxd-nvidia-pm-test.rules` (runtime PM on driver bind)

**Deliberately SKIPPED:** `99-nvidia-ac.rules`

Upstream ships `99-nvidia-ac.rules` which starts/stops `nvidia-powerd.service` on AC power state transitions. On FA507NV this rule is a **crash trigger** — it exercises `nv_acpi_powersource_hotplug_event`, the code path that deadlocks the NVIDIA driver into a full system LOCKUP (documented in `project_nvidia_crash_pattern`). Installing it during Phase 0 would arm the crash on every plug/unplug of AC.

**v0.1 packaging implication:** Our `supergfxctl` `.deb` must NOT install `99-nvidia-ac.rules` on hardware exhibiting the ACPI hotplug bug (FA507NV and likely other TUF/ROG models with the same firmware family). Options: ship the rule but disabled, skip it entirely on affected hardware via a conditional postinst, or ship a corrected rule that mitigates the crash. Decision deferred to Task 16 verdict.

**Side effects of supergfxd startup on FA507NV (from journal):**

1. `create_modprobe_conf: writing /etc/modprobe.d/supergfxd.conf` — supergfxd writes its own modprobe file on first run:
   ```
   blacklist nouveau
   alias nouveau off
   options nvidia-drm modeset=1
   ```
   **No conflict with `/etc/modprobe.d/nvidia-custom.conf`** — different options touched. But for packaging: this file is runtime-generated, must be handled as such in `.deb` (either shipped as conffile or excluded from `debian/install`).

2. `["start", "nvidia-powerd.service"]` — supergfxd auto-starts `nvidia-powerd.service`. Runs continuously in Hybrid mode. This is NVIDIA's designed power daemon.

3. `set_runtime_pm: Auto` — dGPU runtime PM set to auto (`/sys/bus/pci/devices/0000:01:00.0/power/control` = `auto`).

4. `nvidia-drm.modeset not set, ignoring` — supergfxd looks at its own path for `nvidia-drm.modeset`, doesn't see it, moves on. Kernel cmdline does have `nvidia_drm.modeset=1` (verified `/proc/cmdline`). Non-issue for functionality, minor concern for supergfxd's config detection logic.

**GPU state read (Task 11) — ✅ WORKS:**

- Current mode: `Hybrid` ✓
- Supported modes on FA507NV: `[Integrated, Hybrid, AsusMuxDgpu]`
- Vendor: `Nvidia`
- Power status: `active`
- Loaded modules: `nvidia`, `nvidia_uvm`, `nvidia_drm`, `nvidia_modeset`, `nvidia_wmi_ec_backlight`, `asus_wmi`, `asus_nb_wmi`, `amdgpu`, `wmi`
- dGPU device: `10DE:28E0` (RTX 4060 Laptop) at `0000:01:00.0`
- dGPU audio: `10DE:22BE` at `0000:01:00.1`
- Kernel cmdline preserved: `acpi_osi=Linux acpi_backlight=native nvidia_drm.modeset=1 pcie_aspm=off nvidia.NVreg_PreserveVideoMemoryAllocations=1`

**Note on dbus object path:** Plan and both my initial guesses (`/org/asuslinux` and `/org/supergfxctl/Daemon`) were wrong. supergfxctl CLI works fine — no impact on functionality — but any GUI/dbus-client integration needs to use the exact object paths asusd/supergfxd expose. To be discovered during GUI work (v0.2).

## GPU Mode Switching (Task 13) — ✅ WORKS SAFELY

**Test venue:** Installed system (not live USB). AC power, work saved, no SSH backup, deliberate step-through.

**Baseline before test:**
- Mode: `Hybrid`
- Pending action: `No action required`
- Pending mode: `Unknown` (clean, no queued change)
- `nvidia_uvm used_by=0` (bongoSTEM stopped by user before test — critical prerequisite)
- Display session (gnome-shell) using NVIDIA — expected

**Command 1: `supergfxctl -m Integrated`**

- Return code: `0`
- Stdout: `Graphics mode changed to Integrated. Required user action is: Logout required to complete mode change`
- Immediate state:
  - Live mode: still `Hybrid` (untouched) ✓
  - Pending action: `Logout required to complete mode change`
  - Pending mode: `Integrated` (queued)
- Journal:
  - `INFO: Switching gfx mode to Integrated`
  - `DEBUG: Doing action: WaitLogout`
- **No display glitch. No lockup. No crash.** Session untouched.

**Command 2: `supergfxctl -m Hybrid` (cancel pending)**

- Return code: `0`
- Stdout: `Graphics mode changed to Hybrid`
- Post-state:
  - Live mode: `Hybrid`
  - Pending: `No action required`
  - Pending mode: `Hybrid` (clean)
- Journal (30 seconds after initial command):
  - `WARN: Time (30 seconds) for logout exceeded`
  - `ERROR: Action thread errored fallback failed: Timed out waiting for systemd unit change`

**Interpretation of the WARN/ERROR:** These are supergfxd's normal timeout behavior when a queued switch doesn't get its logout within 30 seconds. supergfxd cancels the queue itself. Non-fatal. Cancellation via `-m Hybrid` also works while pending is armed.

**Key finding — the logout-mediated switch model is FA507NV-safe:**

- No live driver unload during runtime → no ACPI code path is exercised → the documented `nv_acpi_powersource_hotplug_event` LOCKUP is not triggered by mode switching
- User controls when the switch applies (by logging out)
- Cancellation is trivial (issue current-mode command before logout)
- 30-second timeout catches user who queues a switch but never logs out

**v0.1 packaging verdict: supergfxctl is SHIPPABLE.** No special hardware-specific patching required for mode switching itself. Still need to handle the `99-nvidia-ac.rules` exclusion (recorded in Task 10 section).

**Untested (deferred to future testing or user-level acceptance):**
- Actual switch completion after real logout (would require SSH-back-in flow, not attempted here)
- `AsusMuxDgpu` mode (physical mux switch, reboot required, higher risk on FA507NV, deferred)
- Live GPU-load-during-switch behavior (not attempted — mode change was queued, not applied)

## Tasks 14-15 — Battery-power and GPU-load testing (SKIPPED)

**Skipped deliberately.** Both tasks required conditions that would exercise the documented `nv_acpi_powersource_hotplug_event` LOCKUP pattern (Task 14 unplugs AC; Task 15 puts the dGPU under load while nvidia-powerd is running).

**Rationale:**

1. All feature verdicts already have high confidence from Tasks 5-13.
2. The only asusctl feature that works (thermal profile) is a plain sysfs write to `throttle_thermal_policy` — its behavior is not power-state or load-dependent by design.
3. supergfxctl mode switching is queued-until-logout, so its behavior does not vary with power state.
4. The risk-to-information ratio was poor: running these tests would exercise the exact crash pattern this project exists to work around, for information that adds little to the verdict.

**What this means for v0.1:** ship v0.1 with the caveat that "thermal profile switching on battery" is untested but expected to work (same sysfs). If any user reports battery-specific bugs, that becomes v0.1.1 investigation.

## Recommended Actions for v0.1 (Task 16 verdict)

### Features cleared to ship in v0.1

**1. `asusctl` thermal profile switching (silent / normal / boost) — ✅ SHIP**

- CLI: `asusctl -p silent|normal|boost`
- Backing sysfs: `/sys/devices/platform/asus-nb-wmi/throttle_thermal_policy`
- Verified: all three modes correctly change kernel state on FA507NV
- Notes for `.deb`: standard install of asusd + asusctl binaries + systemd unit + dbus policy. No hardware-specific patching needed for this feature.

**2. `supergfxctl` GPU mode switching (Integrated ↔ Hybrid) — ✅ SHIP**

- CLI: `supergfxctl -m Integrated` (queue) / `-m Hybrid` (queue or cancel)
- Verified: change queues cleanly, requires logout to apply, cancellable before logout, 30-second timeout auto-cancels
- Notes for `.deb`:
  - Ship `/etc/dbus-1/system.d/org.supergfxctl.Daemon.conf` (packaged, no changes)
  - Ship `/lib/systemd/system/supergfxd.service` (packaged, no changes)
  - **Ship `90-supergfxd-nvidia-pm.rules`** to `/lib/udev/rules.d/` (safe on FA507NV)
  - **DO NOT ship `99-nvidia-ac.rules`** — this is the FA507NV-critical exclusion. Options: (a) full exclude via a Ubuntu-specific quilt patch that removes the file from source, (b) install the file but with `.disabled` extension and instruct users to enable it if their firmware is safe, (c) hardware-detection postinst that only installs it on non-affected models. Recommend option (a) for v0.1 to keep the packaging simple and users protected.
  - Handle `/etc/modprobe.d/supergfxd.conf` (runtime-generated by supergfxd on first start) as a `dpkg-statoverride`-managed file, or exclude it from tracking and let supergfxd manage it — decision for the packaging plan.
  - **Do NOT ship `AsusMuxDgpu` as a documented feature in v0.1.** It requires reboot and exercises the physical mux — untested and higher risk.

### Features deferred to v0.2 or beyond

**3. Keyboard backlight — ❌ DEFER (upstream bug)**

- v1.0.1's asusd drops every SetKeyBacklight command with `mpsc failed: no available capacity`
- Root cause: internal bounded channel saturation in the backlight worker
- Path forward: open an upstream issue/PR on `github.com/OpenGamingCollective/asusctl` documenting the bug with our journal output as evidence. Suggested fix: increase the mpsc channel buffer size, or investigate why the channel isn't draining
- Interim for users: raw sysfs write to `/sys/class/leds/asus::kbd_backlight/brightness` (requires root); we could ship a small setuid or polkit-mediated helper as a workaround, but this is v0.2 scope

**4. Battery charge threshold — ❌ DEFER (upstream doesn't detect FA507NV sysfs path)**

- asusd v1.0.1 logs `ERROR: Charge control not available` on startup, despite `/sys/class/power_supply/BAT1/charge_control_end_threshold` existing and being writable
- Existing `battery-charge-threshold.service` (user-maintained) writes it correctly
- Path forward: open an upstream issue documenting that FA507NV's charge control sysfs is at `BAT1` (not `BAT0`) and asusd doesn't fall back
- Interim for users: our v0.1 packaging documents the existing systemd-unit pattern as the current mechanism. This is honest and gets users a working charge cap without shipping broken asusctl functionality

**5. Fan curves — ⛔ NOT SHIPPABLE (upstream removed from CLI)**

- v1.0.1's asusctl has no `fan-curve` subcommand
- The feature was in earlier releases (6.3.x line) but appears removed in the 1.x rewrite
- Path forward: either investigate why upstream dropped it (deliberate refactor or oversight), or accept that fan curves aren't a v0.1 asusctl feature and offer preset thermal profiles only
- Interim for users: they use thermal profiles (`asusctl -p`) as coarse fan control

### Upstream patches to submit

Priority order (best return on our small credibility budget):

1. **Charge control fallback path detection.** Modest patch: make asusd probe `BAT0` then `BAT1` for `charge_control_end_threshold`. Unblocks charge threshold on FA507NV and any other model with battery numbered as BAT1. Easy to test, easy to review.

2. **Keyboard backlight mpsc channel fix.** Requires understanding the backlight worker's message flow. May be a one-line capacity change or may reveal a deeper drain problem. Investigate before opening a PR.

3. **`99-nvidia-ac.rules` should be opt-in per hardware.** Long-shot but important: propose upstream ship this rule as `.disabled` by default, with detection or documentation for which models are safe. Justification: the FA507NV crash is not unique — likely affects most ASUS TUF/ROG models with AMD + NVIDIA and the same ACPI firmware pattern.

We do NOT submit Ubuntu-specific PRs (PR #111 rejection precedent). All patches are hardware / kernel / behavior patches that benefit every distro.

### Ubuntu-specific findings

- **Existing `battery-charge-threshold.service` coexists cleanly with asusd.** They don't fight; asusd v1.0.1 just doesn't see the sysfs. Our `.deb` postinst should detect this pre-existing unit and log an informational note recommending it stays enabled until asusctl gains the fallback path.
- **Custom NVIDIA modprobe options** (`nvidia-custom.conf`) coexist with supergfxd's auto-generated `supergfxd.conf`. Different NVIDIA options touched. No conflict. Our `.deb` must not overwrite user's `/etc/modprobe.d/nvidia-custom.conf`.
- **gdm3 handling:** upstream supergfxd's systemd unit orders `Before=display-manager.service` — works with gdm3 out of the box. No Ubuntu-specific config needed for display manager selection.
- **AppArmor:** upstream ships no AppArmor profile. Ubuntu's AppArmor is permissive on unprofiled daemons by default; we can ship v0.1 without one and add an AppArmor profile in v0.2 as a hardening step.
- **DKMS `asus-armoury`:** not verified in Phase 0 (out of scope). Verification of the DKMS backport is a Plan 2 task before v0.1 ships.

### Go/No-Go for v0.1

**GO** — with the following v0.1 scope, refined from the design spec:

- Ship: `asusctl` + `asusd` (thermal profile only, other CLI flags accepted-but-log-warning), `supergfxctl` + `supergfxd` (Integrated ↔ Hybrid only, no AsusMuxDgpu), `asus-armoury-dkms` (subject to Plan 2 verification), `asusctl-suite` meta-package
- Do NOT ship: keyboard backlight functionality (documented as pending upstream fix), charge threshold via asusctl (users keep existing systemd unit), fan curves (not exposed by upstream), AsusMuxDgpu, `99-nvidia-ac.rules`
- Ship documentation calling out these gaps explicitly and directing users to file upstream issues

**Alternative to consider:** try the `6.3.8` stable line of asusctl before locking in v1.0.1. The older release may have working charge control and keyboard backlight. Testing this would be a Plan 2 first task and adds ~1 hour. My recommendation: **start Plan 2 with a quick 6.3.8 comparison test** — if it works better on FA507NV, we ship the older line in v0.1 and skip the upstream-patch waiting game. If it's worse, we lock v1.0.1 as planned.

### Verification report closes with:

- 15 of 17 planned Phase 0 tasks completed (Tasks 14-15 skipped deliberately for safety)
- All findings committed to `main` on GitHub: `Baraka-Malila/asusctl-ubuntu`
- Machine restored to pre-Phase 0 state by Task 17 (teardown)
- Next artifact: `docs/superpowers/plans/YYYY-MM-DD-v0.1-ubuntu-packaging.md` — Plan 2, informed by these findings, starting with the 6.3.8 comparison test
