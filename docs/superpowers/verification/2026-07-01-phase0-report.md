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

## Recommended Actions for v0.1

*(filled in by Task 16)*
