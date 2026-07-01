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

## Recommended Actions for v0.1

*(filled in by Task 16)*
