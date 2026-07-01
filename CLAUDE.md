# asus-linux — Claude Code Context

## What This Project Is

Ubuntu/Debian packaging and integration for the ASUS Linux ecosystem (asusctl, supergfxctl). The upstream projects are Fedora/Arch-first; Ubuntu users are left with manual sysfs writes and fragile custom scripts. This project fixes that.

**Scope (see `asus-linux-ubuntu.md` for full brief):**
1. Package `asusd`, `supergfxd`, `asusctl` cleanly for Ubuntu 22.04 (Jammy) and 24.04 (Noble)
2. Integrate with GDM3, nvidia-prime, AppArmor — Ubuntu specifics upstream doesn't handle
3. Publish a PPA on Launchpad
4. Optional: minimal GTK4/libadwaita GUI (Armoury Crate equivalent)

**Test hardware:** ASUS TUF Gaming A15 FA507NV (only machine available for testing).

---

## Hardware Context (This Machine)

- **Model:** ASUS TUF Gaming A15 FA507NV (2023)
- **CPU:** AMD Ryzen (Zen 4)
- **GPU:** NVIDIA RTX 4060 Laptop (8GB VRAM) + AMD iGPU
- **Battery:** 90 Wh design, currently **81.7% health** (~73.5 Wh)
- **Current BIOS:** FA507NV.316 (dated 2024-11-04, likely outdated)
- **OS:** Ubuntu 22.04, kernel 6.8.0-124-generic
- **Distro-managed NVIDIA driver:** 580.x series
- **Bluetooth:** MediaTek MT7922 (btusb)
- **WiFi:** Realtek RTL8852BE

**Known BIOS/ACPI bugs on this machine:**
- Battery reports wrong model (`A32-K55` — from 2012) — DMI/SMBIOS table corruption
- Cycle count not exposed to userspace
- ACPI errors at boot: unresolved symbols for GPP2.WWAN, GPP5.RTL8, THRM._SCP.CTYP, etc.
- `nv_acpi_powersource_hotplug_event` can deadlock NVIDIA driver → hard LOCKUP + full system freeze under GPU load if AC power state changes

**Existing custom fixes on this machine:**
- `/etc/modprobe.d/nvidia-custom.conf` — 4 NVIDIA options (see `project_nvidia_crash_pattern.md`)
- `/etc/systemd/system/battery-charge-threshold.service` — caps charge at 80% (see `project_battery_management.md`)
- Kernel cmdline: `acpi_osi=Linux acpi_backlight=native nvidia_drm.modeset=1 pcie_aspm=off`

---

## Sister Project

**bongoSTEM** at `~/bongoSTEM/` — long-term personal AI companion (voice assistant + chess coaching + articulation training). The user runs both projects. This ASUS project exists in part because bongoSTEM training on the RTX 4060 exposed the nvidia ACPI crash bug. Keep them separate — that's why this project has its own directory.

---

## Coding Rules

### 1. File Length Hard Limit: 300 Lines

No file may exceed 300 lines. Split proactively when a file approaches 250 lines.

### 2. One Responsibility Per File

Each file must answer "what does this do?" in one sentence. If the answer has "and", it needs splitting.

### 3. Comments: Why Only

Never comment WHAT the code does — the names do that. Only comment non-obvious constraints, workarounds, or invariants. One line max. No multi-line docstrings.

### 4. No Premature Abstractions

Three similar functions is not a reason to abstract. Wait for the fourth and only if the pattern is fully clear.

### 5. Validate at System Boundaries Only

Validate user input (CLI args, dbus messages) and external API responses (upstream binaries). Trust internal function calls.

### 6. Prefer Permanent Fixes

Never suggest workarounds when a root fix exists. Branches and worktrees exist for bold experiments. "Novel" and "complex" are not reasons to avoid an approach — they're often reasons to pursue it. When suggesting a simpler alternative, always acknowledge the bold option first and let the user decide.

### 7. Fail Fast on Config Errors

If a required binary or dbus service is missing, error immediately at startup with a clear message. Do not silently degrade.

### 8. Packaging Discipline

- Debian packaging rules are strict for a reason — follow them (lintian clean by default)
- Never install to `/usr/local/` in a `.deb` — that's for user-managed files
- Systemd units go to `/lib/systemd/system/` (packaged), never `/etc/systemd/system/` (user)
- udev rules to `/lib/udev/rules.d/`, dbus policies to `/usr/share/dbus-1/system.d/`

### 9. Kernel/Driver Discipline

- Never load a kernel module without checking the current one first
- ACPI-touching code needs extra scrutiny — this hardware has known ACPI bugs
- Test changes on this machine before packaging — the upstream code assumes hardware that may not match

---

## Testing Strategy

- **Real hardware only** — no VMs, no emulators. This machine is the only test rig.
- Test each feature on power AND battery to catch state-transition bugs (like the ACPI crash)
- Test each feature idle AND under GPU load (games, ML training) to catch load-dependent bugs
- Keep a rollback plan for anything that touches sysfs/procfs/modprobe — misconfigs can require BIOS boot recovery

---

## Environment

- **OS:** Ubuntu 22.04, zsh shell
- **Repo layout:** TBD (probably `debian/`, `patches/`, `packaging-scripts/`, `docs/`)
- **Upstream we're packaging:**
  - `asusctl` — gitlab.com/asus-linux/asusctl (Rust)
  - `supergfxctl` — gitlab.com/asus-linux/supergfxctl (Rust)

---

## Git Rules

- Remote: TBD (github.com/Baraka-Malila/asusctl-ubuntu likely)
- Never commit personal `.env` or credential files
- Never commit compiled binaries — build artifacts stay in `debian/build/` (gitignored)

---

## Project Philosophy

- **Clarity over cleverness** — this is packaging work, someone else will read your control files
- **Additive over invasive** — don't fork upstream if a downstream packaging layer suffices (Option C in the planning doc)
- **Small, real users first** — ASUS TUF users in East Africa / South Asia / LatAm need this most, and they're not going to install a random PPA lightly. Trust must be earned via clean packaging.
- **Never break the test machine** — this is Baraka's daily driver. Rollback plans mandatory for anything that touches boot/init.
