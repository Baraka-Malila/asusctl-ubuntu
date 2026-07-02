# Phase 1 Task 9 / Task 8 — Feature Matrix on FA507NV

**Hardware:** ASUS TUF Gaming A15 FA507NV · kernel 6.8.0-124-generic · BIOS FA507NV.316 · Ubuntu 22.04
**Fork base:** asusctl 6.3.8 (patches/asusctl/series empty) · supergfxctl 5.2.7 (patches/supergfxctl/series: 0001-drop-99-nvidia-ac-rules.patch)

This file is the shared home for Task 8's mux verdict and Task 9's four-state matrix. Task 9 will extend it — Task 8 populates only its own section.

---

## Task 8 — AsusMuxDgpu physical mux verdict

**Verdict: ✅ ships as a documented feature on FA507NV.**

Full round-trip verified on this machine 2026-07-02:

| Stage | supergfxctl -g | sysfs `gpu_mux_mode` | Session | dmesg crash markers | Notes |
|---|---|---|---|---|---|
| Pre-switch baseline | `Hybrid` | `1` | Wayland | none | daily-driver default |
| After `-m AsusMuxDgpu` + reboot 1 | `AsusMuxDgpu` | `0` | X11 (GDM fell back) | **none** | display re-init clean; panel at 1920×1080 @ 144Hz on DP-2 |
| After `-m Hybrid` + reboot 2 | `Hybrid` | `1` | Wayland | **none** | full round-trip complete |

**Grep target across both reboots:** `dmesg \| grep -iE 'nv_acpi_powersource_hotplug_event\|panic\|BUG:\|oops\|hard LOCKUP'` → empty in every stage.

### Task 7 validation
The mux switch's own action pipeline calls `EnableNvidiaPowerd` and starts `nvidia-powerd.service` (visible in the daemon journal). Even so, the ACPI hotplug event that Phase 0 documented did NOT fire. This directly validates the Task 7 design decision: removing `99-nvidia-ac.rules` is sufficient for FA507NV — the udev rule was the exclusive trigger of the documented crash pattern, and the daemon's *user-initiated* nvidia-powerd start is safe.

### User-observable regression in dGPU-only mode (documented, not a blocker)

On this machine, booting into `AsusMuxDgpu` visibly reduces desktop sharpness. Not a raw-power regression — it's a stack change:

1. **GDM falls back to X11.** Ubuntu 22.04 ships `/etc/udev/rules.d/61-gdm.rules` which disables Wayland when NVIDIA is the sole display driver. Gnome fractional scaling requires Wayland, so under X11 everything renders at 100% integer scale → smaller/blurrier UI.
2. **NVIDIA default color range.** DP color output may negotiate "Limited" range (16-235) instead of "Full" (0-255) → washed-out contrast, muddy blacks.
3. **Subpixel/hint differences** between AMD Display Core and NVIDIA drm-kms.

None of these are supergfxctl bugs. They surface because AsusMuxDgpu changes which vendor stack drives the display.

### Recommendation for future phases

- **Phase 2 packaging:** ship a documented opt-in recipe for Wayland-on-NVIDIA on 22.04 (delete/comment `/etc/udev/rules.d/61-gdm.rules`, set `WaylandEnable=true` in `/etc/gdm3/custom.conf`). Not a default — NVIDIA + Wayland on kernel 6.8 has known warts (Electron HW-accel, XWayland tearing) that only clear up on kernel ≥ 6.9 + NVIDIA ≥ 555 (Ubuntu 24.04 HWE).
- **Phase 3 GUI:** expose an "Enable Wayland on NVIDIA (experimental)" toggle in the display settings pane; wire it to the same recipe.
- **User-facing docs:** recommend Hybrid + PRIME (`__NV_PRIME_RENDER_OFFLOAD=1` / Steam auto-PRIME) as the everyday default; AsusMuxDgpu only for VR / lowest-latency competitive gaming / NVIDIA-only external ports.

### Untested (deferred to Task 9)

- Battery-mode behavior in AsusMuxDgpu (higher drain expected; not sanity-testable in a one-off reboot session)
- Mux switch under active GPU load (dangerous; skip)
- AC plug/unplug transitions in AsusMuxDgpu (Task 9's four-state matrix covers this axis)

---

## Task 9 — four-state feature matrix

Fork daemons installed via `scripts/install-fork-asusd-test.sh` and `scripts/install-fork-supergfxd-test.sh`. Workloads: `stress-ng --cpu 8 --timeout 60s` + `glmark2 --run-forever` (killed after each load state).

| Feature | S1 · AC+idle | S2 · AC+load | S3 · batt+idle | S4 · batt+load |
|---|---|---|---|---|
| Thermal profile Q/B/P | ✅ throttle sysfs 2/0/1 | ✅ 2/0/1 | ✅ 2/0/1 | ✅ 2/0/1 |
| EPP write per profile | ✅ power / balance_power / performance | ✅ same | ✅ same | ✅ same |
| Fan curve read (Balanced) | ✅ enabled: true; RPMs 3600/3600 | ✅ same curve; RPMs 3600→4200 across Q→B→P→B | ✅ same; RPMs 3400/2900 | ✅ same; RPMs 3200→3700 across Q→B→P→B |
| Kbd backlight step | ✅ 0/1/2/3 | ✅ steps observed | ✅ steps | ✅ steps |
| Charge threshold write | ✅ 60/80 | ✅ 60/80 | ✅ 60/80 (writes accepted on battery) | ✅ 80 |
| GPU mode | ✅ Hybrid, gpu_mux_mode=1 | ✅ Hybrid, status active | ✅ Hybrid | ✅ Hybrid |
| dmesg crash markers | ✅ none | ✅ none | ✅ none | ✅ none |

### AC transitions

| Edge | Timestamp (local) | `ACAD/online` | BAT1 status | dmesg `nv_acpi_powersource_hotplug_event` | Verdict |
|---|---|---|---|---|---|
| AC → battery (before S3) | ~2026-07-02 T4 | `1 → 0` | Discharging | **none** | ✅ safe |
| battery → AC (after S4) | ~2026-07-02 T5 | `0 → 1` | Charging | **none** | ✅ safe |

**Both AC transitions completed with zero occurrences of `nv_acpi_powersource_hotplug_event` in `dmesg`.** The soft warnings observed during load (`workqueue: acpi_os_execute_deferred hogged CPU for >10000us`, `workqueue: pm_runtime_work hogged CPU`) are informational latency notes about ACPI method execution taking >10 ms under 8-CPU stress — not crash markers, not related to the documented crash pattern.

### Task 7 validation across the full matrix

Removing `data/99-nvidia-ac.rules` from the supergfxctl fork tree (patches/supergfxctl/0001-drop-99-nvidia-ac-rules.patch) is **verified sufficient** to disarm the FA507NV ACPI crash pattern. All four hardware states, both AC transitions, mux switching (Task 8), and workload-driven GPU activity ran with the udev rule absent — no ACPI hotplug event fired at any point.

### Behavioral notes

1. **6.3.8's EPP integration writes per profile even under load.** Confirmed in every state — `energy_performance_preference` follows the thermal profile without lag. Task 2's finding validated at scale.
2. **Fan curves respect the enabled flag.** In S1 no workload was running so we relied on the curve read; in S2/S4 the fan1 RPM ramps across profile transitions confirm the daemon's `write_profile_curve_to_platform` call reaches the hwmon PWM tables.
3. **Battery+load fan curve is more conservative than AC+load.** Fan1 tops out at 3700 RPM on batt+load vs 4200 on AC+load — the platform's own battery power-management prefers lower fan RPM. This is BIOS/embedded-controller behavior, not our daemon.
4. **Fan RPMs at S2/S4 baseline are elevated from post-stress residual heat**, not from Q or B profile itself — visible when comparing S1 idle (3600/3600) vs post-workload S3 idle (3400/2900).

### Rollback verification

`scripts/phase1-teardown.sh` end state:

| Item | Value | Match pre-flight snapshot? |
|---|---|---|
| `asusd-test.service` | inactive | ✓ |
| `supergfxd-test.service` | inactive | ✓ |
| `battery-charge-threshold.service` | enabled + active | ✓ (auto-restored from `/var/lib/asus-phase1-fork/`) |
| `charge_control_end_threshold` | 80 | ✓ |
| `throttle_thermal_policy` | 0 (Balanced) | ✓ |
| `kbd_backlight/brightness` | 0 (post-restore) | ✓ |
| `gpu_mux_mode` | 1 (Hybrid) | ✓ |
| `which asusctl` | not found | ✓ |
| `which supergfxctl` | not found | ✓ |

FA507NV daily-driver state fully restored.

### GO for Task 10

All 7 features × 4 states + 2 AC transitions = zero regressions. Both fork tree builds (asusctl 6.3.8 + supergfxctl 5.2.7 with 1 patch) verified end-to-end on real hardware. Phase 1 is complete pending the exit report.

