# Design decision: blacklist `nvidia_wmi_ec_backlight` on FA507NV-family hardware

**Date:** 2026-07-03
**Scope:** Phase 2 packaging (asusctl-suite postinst or a dedicated `asus-backlight-fix` micro-package). Not asusd source. Diagnosed at end of Phase 1 Task 9.5.

---

## Problem

On ASUS TUF Gaming A15 FA507NV (Ryzen + Radeon iGPU + NVIDIA RTX 4060 dGPU) running Ubuntu 22.04 (kernel 6.8, GNOME 42/44), the display brightness slider works only *intermittently*. Sometimes dragging it dims the screen; sometimes it silently no-ops.

## Diagnostic (verified on FA507NV, 2026-07-03)

Two backlight interfaces register at boot:

| Interface | Sysfs path | Role |
|---|---|---|
| `amdgpu_bl1` | `.../drm/card1/card1-eDP-1/amdgpu_bl1/` | **Real panel controller** (eDP-1 is the physical laptop panel, driven by the AMD iGPU compositor path in Hybrid mode) |
| `nvidia_0` | `.../0000:01:00.0/backlight/nvidia_0/` | **Shadow interface** exposed by the `nvidia_wmi_ec_backlight` kernel module; PCI parent is the NVIDIA dGPU |

gsd-power (GNOME Settings Daemon Power) picks *one* backlight to write to at session start / resume, via udev's `BACKLIGHT` type-tag heuristics. On FA507NV both interfaces receive equivalent tags, so the choice is effectively racy:

- **Boot A:** gsd-power picks `amdgpu_bl1` — brightness slider works
- **Boot B:** gsd-power picks `nvidia_0` — brightness slider writes to a shadow interface the physical panel doesn't obey → visible no-op
- **Suspend / resume:** picks can flip, matching the "sometimes works" pattern

Diagnostic captured live:
- Direct sysfs writes to `amdgpu_bl1` (255→64, 3s) and `nvidia_0` (48→10, 3s) produced no visible dimming — neither is the sole owner at that moment, and gsd-power (or the kernel) was racing to overwrite.
- 10 s inotify-watch of both interfaces while the user dragged the GNOME slider showed **zero writes to either sysfs**. gsd-power had detached — the fallback race we're describing.

## Chosen fix

Blacklist `nvidia_wmi_ec_backlight`. That prevents `nvidia_0` from registering as a backlight interface at boot. `amdgpu_bl1` becomes the sole entry under `/sys/class/backlight/`; gsd-power has nothing to race against; slider works deterministically.

### Content shipped

`/etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf` (final packaged name):

```
# Blacklist NVIDIA WMI EC backlight shadow interface on FA507NV-family hardware.
# It races with amdgpu_bl1 (the real panel controller for eDP-1) inside
# gsd-power, causing the GNOME brightness slider to silently no-op ~half
# the time. Removing the shadow leaves amdgpu_bl1 as the sole backlight
# entry, which gsd-power picks unambiguously.
blacklist nvidia_wmi_ec_backlight
```

`update-initramfs -u` is required so the blacklist takes effect at early boot. Handled by the package's postinst.

## Why not a udev-tag override

An alternative would be a udev rule that force-tags `amdgpu_bl1` as the preferred backlight and `nvidia_0` as raw. Rejected because:

- udev-based backlight tagging changed between systemd versions (249 vs 250+ behave differently)
- gsd-power's own priority heuristic changes between GNOME 42, 44, and 46
- The blacklist is simpler, hardware-family scoped, and has one failure mode instead of three

## Why not a Rust patch to asusd

asusd doesn't touch display backlight (only `asus::kbd_backlight`). This bug lives in the kernel + gsd-power interaction. A patch to asusd would be out of layer.

## Hardware gating for Phase 2

The blacklist applies specifically to laptops that expose BOTH:
- `amdgpu_bl?` under a `card?-eDP-?` DRM path (i.e. AMD iGPU driving the internal panel)
- `nvidia_0` under a NVIDIA dGPU PCI address

FA507NV matches both. Other affected models likely include the wider FA507N* line, FA707N*, and NVIDIA-hybrid TUF/ROG models with AMD iGPUs. The postinst should detect this configuration and skip the blacklist on:

- ROG laptops with Intel iGPU (Intel drives `intel_backlight`; no amdgpu_bl race)
- TUF laptops with only NVIDIA driving the panel (AsusMuxDgpu-permanent setups)
- Machines without the `nvidia_wmi_ec_backlight` module loaded

Recommended detection logic (postinst pseudo-code):

```sh
if lsmod | grep -q nvidia_wmi_ec_backlight \
   && ls /sys/class/backlight/amdgpu_bl* >/dev/null 2>&1 \
   && ls /sys/class/backlight/nvidia_0    >/dev/null 2>&1 ; then
    install_blacklist
fi
```

## Interaction with AsusMuxDgpu mode

If the user physically muxes to `AsusMuxDgpu` (NVIDIA-only display), `amdgpu_bl1` may no longer be the correct backlight — the panel is driven by NVIDIA and `nvidia_0` becomes the right interface. The blacklist would then *break* brightness control in dGPU-only mode.

Two mitigations for Phase 2 (choose during packaging design):

- **A. Mux-aware toggle.** Ship a small `asusctl-backlight-toggle-mux` helper that supergfxctl invokes on mux-mode change (via a systemd path unit or post-mode hook). In Hybrid/Integrated: blacklist active. In AsusMuxDgpu: blacklist file renamed aside + `modprobe nvidia_wmi_ec_backlight`.
- **B. Document and defer.** Users who intentionally switch to AsusMuxDgpu are aware of the tradeoff. troubleshoot.md notes the manual revert step.

Option A is cleaner; option B ships faster. Task 10 exit report should flag this open decision.

## Rollback

`apt purge asusctl-suite` should delete the modprobe file. `update-initramfs -u` on postrm. Panels revert to the original race-with-shadow behavior — user is no worse off than pre-install.
