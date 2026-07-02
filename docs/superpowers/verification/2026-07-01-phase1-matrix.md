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

## Task 9 — four-state matrix

*(To be populated by Task 9. Structure will be: rows = features, columns = AC+idle, AC+load, battery+idle, battery+load.)*
