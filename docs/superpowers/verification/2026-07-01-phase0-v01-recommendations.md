# Phase 0 Verdict — v0.1 Feature Scope and Fix Plan

**Source of evidence:** `2026-07-01-phase0-report.md` (raw findings from hardware verification on FA507NV)

**Date:** 2026-07-01 (revised same day after reframe: we are an independent Ubuntu-first fork, not a downstream layer)

**Purpose:** Drive Plan 2 (v0.1 packaging + fixes) with the correct framing — we ship a working product, not upstream's brokenness with documentation.

---

## Framing correction from earlier in the session

The initial verdict split features into "ship" and "defer to v0.2, pending upstream fix." That framing is wrong for this project. We are not upstream's downstream. OGC rejected Ubuntu support. Their code works on their hardware. On FA507NV it doesn't — and that is our problem to solve, not theirs. Users installing `asusctl-suite` on Ubuntu should get an Armoury-Crate-equivalent working tool. Every feature that Armoury Crate offers and that the hardware supports must ship. If upstream's implementation is broken on our hardware, we fix it in our tree. Nothing is deferred to a hypothetical upstream release.

## v0.1 Feature Scope (all working, all shipping)

| Feature | Upstream state on FA507NV | Our v0.1 action |
|---|---|---|
| Thermal profile switching | Works | Ship as-is |
| GPU mode switching (Integrated ↔ Hybrid) | Works | Ship as-is |
| Keyboard backlight | Broken (mpsc drop) | **We patch asusd's backlight channel and ship the fix** |
| Battery charge threshold | Broken (BAT1 not detected) | **We patch asusd's sysfs probe to iterate BAT0..BAT9 and ship the fix** |
| Fan curves | Dropped from v1.0.1 CLI | **We restore fan-curve CLI (backport from 6.3.x or hit hwmon directly) and ship it** |
| 99-nvidia-ac.rules (crash trigger) | Ships armed | **We ship a safe replacement or ship it disabled with clear docs** |
| AsusMuxDgpu (physical mux) | Untested | **We test it thoroughly in Plan 2 and ship if working** |

**v0.1 target:** all seven rows shipped and working on FA507NV. No caveats, no "expected to work but untested," no "will be fixed after upstream merges."

## Fix implementation approach

### 1. Keyboard backlight — patch asusd

- Location: `upstream/asusctl/asus-nb-ctrl/src/ctrl_leds.rs` (Phase 0 discovered `kbd_node` field lives here; the mpsc worker is nearby)
- Bug: `WARN: SetKeyBacklight over mpsc failed: no available capacity` on every command
- Fix: identify the mpsc channel creation, either bump bounded capacity to a sane value (e.g., 32) or fix the drain-side worker if commands are being enqueued faster than consumed
- Ship path: patch lives in our `patches/` quilt series applied to upstream tarball at build time

### 2. Charge threshold — patch asusd

- Location: asusd's power-supply detection (grep the source for `charge_control_end_threshold` or `BAT0`)
- Bug: asusd probes `BAT0` only; FA507NV exposes charge control at `BAT1`
- Fix: iterate `BAT[0-9]` in `/sys/class/power_supply/` and use the first one that has `charge_control_end_threshold`
- Ship path: patch in our `patches/` series
- Bonus: our `.deb` postinst detects the existing `battery-charge-threshold.service` and offers to disable it (with user confirmation) since our patched asusd now handles the same job cleanly

### 3. Fan curves — restore CLI subcommand

Two paths, decide in Plan 2:

- **Path A: backport 6.3.x code.** The `fan-curve` subcommand and its asusd handler existed in 6.3.8. Bring the code back on top of 1.0.1's newer architecture. Risk: 1.x may have refactored asusd internals such that backporting is non-trivial.
- **Path B: write our own `asusctl-fanctl` CLI.** Small independent binary that reads/writes `hwmon` PWM directly, respects our thermal profile, and doesn't rely on asusd. Simpler, but a new binary to maintain.

Plan 2's first task on this line: read the 6.3.8 code, estimate backport effort, pick Path A or B.

### 4. 99-nvidia-ac.rules — safe replacement

- Upstream rule: on AC connect start nvidia-powerd, on AC disconnect stop it — the exact trigger for `nv_acpi_powersource_hotplug_event` LOCKUP on FA507NV
- Our replacement (candidate design): only stop nvidia-powerd on battery, never restart it automatically on AC — user restarts via a systemd unit at login, or nvidia-powerd starts under gdm3's control. Avoids the AC-connect hotplug event entirely.
- Fallback if the safe replacement proves complex: ship the rule as `.disabled` and offer a `sudo asusctl-enable-ac-rule` command that arms it, with a clear warning about the FA507NV crash pattern. Users with tested-safe firmware opt in.

### 5. AsusMuxDgpu (physical mux) — verify then ship

- Skipped in Phase 0 due to reboot requirement + higher risk
- Plan 2 dedicates one testing session to try it: baseline, `-m AsusMuxDgpu`, reboot, verify NVIDIA-only mode works, `-m Hybrid`, reboot, verify Hybrid restored
- If it works cleanly on FA507NV, ship it as a documented feature
- If it produces a hard failure requiring recovery, ship with a warning or hide behind a config flag

## 6.3.8 comparison test — first task in Plan 2

Still recommended, but for a different reason than before. We're not choosing between "ship 6.3.8 unchanged" or "ship 1.0.1 unchanged." We're picking the best base to fork from, then applying our patches on top. If 6.3.8's fan-curve code is intact and its mpsc pattern is sound, it may be the better base. If 1.0.1's queued GPU switch design is cleaner (it is), we may want to backport that INTO 6.3.8 rather than the other way around.

Plan 2 first task: build 6.3.8 on FA507NV, run the same feature verification, produce a side-by-side. Pick base branch informed by real data.

## Ubuntu integration (unchanged from prior verdict)

- Existing `battery-charge-threshold.service` coexists; our postinst offers migration to patched asusd
- Custom NVIDIA modprobe options (nvidia-custom.conf) coexist; our packaging does not touch it
- gdm3 works out of the box with supergfxd's systemd ordering
- AppArmor profile deferred to v0.2 (hardening layer, not a feature blocker)
- DKMS `asus-armoury` for pre-6.19 kernels is Plan 2 verification scope

## Ubuntu version target (unchanged)

- v0.1: Ubuntu 22.04 Jammy + 24.04 Noble
- v0.2: add 26.04 Resolute
- v0.3: add Debian bookworm/trixie

## Go/No-Go for v0.1

**GO** — with the corrected scope above. Every feature ships working. No deferrals.

## Plan 2 first-tasks (in order)

1. Build 6.3.8 alongside 1.0.1, run parallel feature verification, decide which is the better fork base
2. Set up the fork model: our `patches/` quilt series, our build tree, our binary output
3. Patch keyboard backlight (mpsc) — smallest fix, unlocks a feature
4. Patch charge threshold (BAT probe) — small fix, unlocks another feature
5. Fan curve restoration (Path A backport or Path B independent binary)
6. Safe 99-nvidia-ac.rules replacement
7. AsusMuxDgpu verification
8. Thermal profile on battery (safety test: stop nvidia-powerd first, then unplug)
9. asus-armoury DKMS packaging
10. `debian/` control files + PPA setup on Launchpad
11. GitHub Actions CI (build + lintian on Jammy + Noble)
12. User docs (install.md, troubleshoot.md)
13. First PPA release

Number of tasks is larger because scope is larger. Value proposition is proportionally larger too — this is Armoury Crate for Ubuntu, not a diagnostic tool that says "sorry, this feature is broken upstream."
