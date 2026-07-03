# Phase 2a Task 2 — `kbd_brightness_on_power` verification on FA507NV

**Date:** 2026-07-03
**Patch under test:** `patches/asusctl/0002-kbd-brightness-on-power.patch`
**Config used:** `change_kbd_brightness_on_power: true`, `kbd_brightness_on_ac: High`, `kbd_brightness_on_battery: Off`.

## Setup

`scripts/install-fork-asusd-test.sh` installed the patched asusd. asusd.ron edited via `sed -i` to enable the automation with observably-different levels. Daemon restarted.

Baseline: ACAD/online=1 (on AC), kbd sysfs=0 (kbd was off from prior teardown, before setting the daemon-driven target).

## Bidirectional transition

| Timestamp | Edge | ACAD/online | Journal (grep `sysfs power watcher\|kbd brightness`) | kbd sysfs post-transition |
|---|---|---|---|---|
| 02:34:12 | AC → battery | `1 → 0` | `AC state changed, plugged=false` + `kbd brightness -> Off` | `0` |
| 02:35:00 | battery → AC | `0 → 1` | `AC state changed, plugged=true` + `kbd brightness -> High` | `3` |

User visually confirmed the LED lit up on the AC-plug edge.

Watcher latency: ~2-5 s from physical action to sysfs write (matches the 2 s polling cadence + shell timing).

## Opt-out verification

Set `change_kbd_brightness_on_power: false` in asusd.ron, restart daemon. Sysfs pre-cycle: 2 (Med, set manually as a distinct sentinel).

| Timestamp | Edge | ACAD/online | Journal (same grep) | kbd sysfs post-transition |
|---|---|---|---|---|
| 02:35:56 | AC → battery | `1 → 0` | `AC state changed, plugged=false` (no `kbd brightness` line) | `2` (unchanged) |
| 02:36:30 | battery → AC | `0 → 1` | `AC state changed, plugged=true` (no `kbd brightness` line) | `2` (unchanged) |

**Watcher still fires on AC edges** (needed for Phase 1 profile automation). The opt-in flag cleanly guards *only* the kbd-write path.

## Teardown

`scripts/phase1-teardown.sh` ran clean. Manual restore of thermal / kbd / charge to pre-flight snapshot values. FA507NV state matches `/var/lib/asus-phase1-fork/phase2a/`.

## Verdict

Task 2 ships. Default (opt-out) behavior is byte-identical to Phase 1. Opt-in produces the expected sysfs writes on both edges with ~2-5 s watcher latency. No warnings, no failed writes, no regressions in the other Phase 1 automations that share the same watcher.
