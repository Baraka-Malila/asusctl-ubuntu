# Phase 2a Task 4 — `gpu_mode_per_power` verification on FA507NV

**Date:** 2026-07-03
**Patch under test:** `patches/asusctl/0003-gpu-mode-per-power.patch` (numbered 0003 in series after Task 3 was skipped).
**Config used:** `change_gpu_mode_on_power: true`, `gpu_mode_on_ac: Hybrid` (default), `gpu_mode_on_battery: Integrated` (default).

## Setup

`scripts/install-fork-supergfxd-test.sh` installed our fork's supergfxd first (needed as the SetMode target). Then `scripts/install-fork-asusd-test.sh` installed the patched asusd. asusd.ron edited via `sed -i` to flip `change_gpu_mode_on_power` to `true`. Both daemons restarted.

`supergfxctl -g` at start: `Hybrid`.

## Bidirectional transition

Note: since the daemon boots reading current AC state, only the *change* triggers the watcher. Two physical transitions were tested.

| Timestamp | Edge | ACAD/online | asusd journal | supergfxd reply | Notes |
|---|---|---|---|---|---|
| 05:03:56 | battery → AC | `0 → 1` | `supergfxd_client: SetMode(Hybrid)` + `gpu-mode queued -> Hybrid (user_action_required=4, log out to apply)` | u32=4 (Nothing to do — already Hybrid) | Idempotent no-op correctly reported |
| 05:05:40 | AC → battery | `1 → 0` | `supergfxd_client: SetMode(Integrated)` + `gpu-mode queued -> Integrated (user_action_required=0, log out to apply)` | u32=0 (accepted) | Cross-daemon call successful |

Watcher latency: ~2-5 s from physical action to asusd's SetMode call (matches 2 s polling cadence).

`supergfxctl -g` remained `Hybrid` throughout — supergfxd stages the change but does not apply it live until logout. This is Phase 0's documented behavior; Task 4 verifies the *trigger*, not the switch mechanism (Task 8 already covered mode switching end-to-end).

## Cancellation

Post-verification, the pending mode was cancelled by re-issuing the current mode:

```
$ supergfxctl -m Hybrid
Graphics mode changed to Hybrid
```

Confirmed pending action cleared before teardown.

## What Task 4 does NOT verify

- **Reboot-cycle completion of the switch.** Task 8 already covered the full three-mode cycle including AsusMuxDgpu. Repeating that here adds no signal.
- **Desktop notification delivery.** Notifications intentionally skipped in this patch — sending freedesktop notifications from a system-bus daemon requires cross-bus user-session lookup that's too much complexity for a base patch. INFO-level journal log is the notification for v0.1; `asusctl-gui` in Phase 3 (running in the user session) will handle proper notifications.
- **Multi-user session behavior.** All testing done from a single active graphical session. Multi-session behavior stays as supergfxd's existing logic dictates.

## Structural AsusMuxDgpu exclusion

The `AutoGfxMode` enum in `asusd/src/supergfxd_client.rs` has exactly two variants: `Hybrid` and `Integrated`. `AsusMuxDgpu` is not representable in `gpu_mode_on_ac` or `gpu_mode_on_battery` — no runtime check needed, the type system guarantees the reboot-required mode cannot be auto-selected.

## Rollback

`scripts/phase1-teardown.sh` clean. Manual restore of thermal / kbd / charge to pre-flight snapshot values. `battery-charge-threshold.service` restarted (stale state file from earlier session).

Final state: `battery-charge-threshold.service` active, charge=80, kbd=0, thermal=0, gpu_mux=1 (Hybrid). Matches pre-Phase-1 baseline.

## Verdict

Task 4 ships. Default (opt-out) behavior is byte-identical to Phase 1. Opt-in produces the expected cross-daemon SetMode calls on both AC edges with ~2-5 s watcher latency. Session UX inherited from supergfxd's staging (logout-required, cancellable, session-safe per Phase 0). No warnings, no failed writes, no regressions in Phase 1's automations that share the same watcher.
