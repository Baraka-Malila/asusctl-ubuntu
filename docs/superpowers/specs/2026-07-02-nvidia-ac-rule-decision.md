# Design decision: `99-nvidia-ac.rules` is removed from our supergfxctl fork

**Date:** 2026-07-02
**Scope:** Phase 1 Task 7. Applies to `fork/supergfxctl/` (base tag 5.2.7) and the Phase 2 debian packaging of `supergfxctl`.

## Decision

Remove `data/99-nvidia-ac.rules` from the supergfxctl source tree entirely. Ship as `patches/supergfxctl/0001-drop-99-nvidia-ac-rules.patch`.

Neither our fork's `make install` nor our Phase 2 debian packaging shall install any udev rule that starts or stops `nvidia-powerd.service` in response to a power-supply `POWER_SUPPLY_ONLINE` change.

## Why

`99-nvidia-ac.rules` upstream contains two lines:

```
SUBSYSTEM=="power_supply",ENV{POWER_SUPPLY_ONLINE}=="0",RUN+="/usr/bin/systemctl --no-block stop nvidia-powerd.service"
SUBSYSTEM=="power_supply",ENV{POWER_SUPPLY_ONLINE}=="1",RUN+="/usr/bin/systemctl --no-block start nvidia-powerd.service"
```

On ASUS TUF Gaming A15 FA507NV (and, based on shared firmware family, likely other TUF/ROG models of the same generation), starting or stopping `nvidia-powerd` in response to an AC state change exercises the NVIDIA proprietary driver's `nv_acpi_powersource_hotplug_event` code path. Under GPU load, that code path can deadlock the driver, producing a full-system kernel LOCKUP and hard freeze that requires a hardware reset.

The crash is documented in `memory/project_nvidia_crash_pattern.md`. It is the reason this project exists. It also motivates the existing `/etc/modprobe.d/nvidia-custom.conf` mitigations on the daily-driver machine.

## Why removal (not modification) is the right call

Three options were considered from the Task 7 plan:

- **7a — never start/stop on AC transitions.** Ship as `.disabled`. Ship a supergfxd-managed systemd unit that starts `nvidia-powerd` once at login.
- **7b — stop-only on battery, no restart on AC.** Halves the risk (drops the AC-connect edge), keeps the battery-connect edge.
- **7c — user opt-in.** Ship disabled, provide an `asusctl-enable-ac-rule` helper.

Investigation of upstream 5.2.7 changed the calculus:

1. **Upstream's Makefile (line 49) does not install `99-nvidia-ac.rules`.** It installs only `90-supergfxd-nvidia-pm.rules` (a separate NVIDIA runtime-PM rule, unrelated to AC transitions). The AC rule is *only* shipped in `./data/`; the `install` target has no `INSTALL_DATA` line for it.
2. **Upstream `CHANGELOG.md` line 79** explicitly marks the rule OPTIONAL: *"99-nvidia-ac.rules udev rule added to ./data, this rule is useful for stopping nvidia-powerd on battery as some nvidia based laptops are poorly behaved when it is active (OPTIONAL)"*.
3. **The Rust daemon has no AC-transition handler.** `grep` across `src/` for `POWER_SUPPLY_ONLINE`, `power_supply/AC`, and `nvidia-powerd` shows the only `toggle_nvidia_powerd` callers are the `StagedAction::{Enable,Disable}NvidiaPowerd` variants, which run during *user-initiated* GPU mode switches (integrated ↔ hybrid ↔ dedicated), not on AC events.

So the risk surface is confined to *third-party* packagers or user-installed rules picking up `data/99-nvidia-ac.rules` and manually installing it. AUR's supergfxctl-git package has historically done exactly that; Fedora COPR builds have varied. Any downstream that runs a glob like `install -m 644 data/*.rules /lib/udev/rules.d/` will pull it in.

Options 7a/7b/7c all require ongoing maintenance (a `.disabled` file, a helper, or a systemd unit) to keep the crash trigger disarmed. Removal at the source-tree level is:

- **Self-documenting** (git blame + patch file explain the reason)
- **Diff-inert** (no ongoing code review burden)
- **Copy-safe** (downstream packagers can't grab a file that isn't there)
- **Loss-free** (nothing in the daemon depends on the file)

## What we still ship

- `data/90-supergfxd-nvidia-pm.rules` — NVIDIA VGA/3D runtime-PM rule, keyed on driver `bind`/`unbind`. Not AC-related. Safe on FA507NV. Installed by upstream Makefile line 49.
- `data/90-nvidia-screen-G05.conf` — X11 config for NVIDIA screen output. Not AC-related.
- The daemon itself, which will toggle `nvidia-powerd` only when the user runs `supergfxctl -m <mode>`. A controlled, user-initiated event, not a passive udev fire.

## Verification requirement (deferred to Task 9)

Task 9 runs the four-state hardware matrix. AC transitions (idle and load, in both directions) are covered by that matrix. If any AC transition during Task 9 fires `nv_acpi_powersource_hotplug_event` in `dmesg`, this decision is *not* sufficient — escalate to also patching the daemon's `toggle_nvidia_powerd` to add an FA507NV-family bypass.

## Phase 2 packaging note

In our Phase 2 `debian/supergfxctl.install`, list only the files upstream's Makefile installs. Do not use `data/*.rules` globs. Enumerate:

```
data/90-supergfxd-nvidia-pm.rules  lib/udev/rules.d/
data/supergfxd.service             lib/systemd/system/
data/supergfxd.preset              lib/systemd/system-preset/
data/org.supergfxctl.Daemon.conf   usr/share/dbus-1/system.d/
data/90-nvidia-screen-G05.conf     usr/share/X11/xorg.conf.d/
```

Explicit is safer than glob for a hardware-safety-critical package.
