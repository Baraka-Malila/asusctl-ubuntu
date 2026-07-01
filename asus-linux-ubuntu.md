# ASUS Linux — Ubuntu/Debian Port (Future Project)

**Status:** Idea / Pre-planning  
**Hardware context:** ASUS TUF Gaming A15 FA507NV (AMD Ryzen + RTX 4060 Laptop, Ubuntu 22.04)  
**Motivation:** ASUS on Windows is a feature-complete, polished experience (Armoury Crate,
MyASUS). On Linux it's a collection of workarounds with no unified control surface.

---

## The Problem

On Windows, ASUS ships:
- **Armoury Crate** — fan curves, thermal profiles (Silent/Balanced/Performance/Turbo),
  GPU mode switching (Optimus/dGPU-only/iGPU-only), battery charge limit, RGB/AuraSync
- **MyASUS** — system diagnostics, warranty status, driver updates, display calibration
- **GPU Mode Switch** — true hardware-level switching between iGPU-only (battery saver)
  and dGPU-active (performance) without reboot on modern models
- **Scenario Profiles** — auto-switch thermal profile based on running app

On Linux you get none of this out of the box. Every feature requires manual sysfs writes,
kernel parameters, and custom services that don't survive updates cleanly.

---

## What Already Exists

### asusctl (gitlab.com/asus-linux/asusctl)
- **Language:** Rust
- **Maintainer:** Luke Jones + ~10 contributors, actively maintained (as of 2026)
- **Supported distros:** Fedora, openSUSE, Arch (AUR) — **no Ubuntu/Debian packages**
- **Features implemented:** thermal profiles, fan curves, AuraSync RGB, battery charge
  limit, anime matrix (on ROG models), keyboard backlight, PRIME GPU switching via supergfxctl
- **Backend:** communicates with `asusd` daemon via dbus; reads ASUS WMI kernel interface

### supergfxctl (gitlab.com/asus-linux/supergfxctl)
- GPU mode management: integrated / hybrid / NVIDIA / vfio
- Same situation: no Ubuntu packages

### asus-nb-wmi (in-kernel)
- Linux kernel module (upstream since ~5.15) for ASUS WMI interface
- Exposes sysfs entries: `throttle_thermal_policy`, fan speeds, battery thresholds
- This is the foundation everything else sits on — it works on Ubuntu

---

## Why No Ubuntu Package?

Several converging reasons:

1. **Maintainer ecosystem**: Luke Jones uses Fedora. RPM packaging is what he knows.
   Ubuntu/Debian `.deb` packaging is a different skill set and nobody stepped up.

2. **Hardware diversity is real**: ASUS ships 50+ distinct laptop lines per year (ROG Zephyrus,
   TUF Gaming, VivoBook, ProArt, ZenBook, ROG Ally). Each has different fan controllers,
   different WMI implementations, different RGB hardware. A package that works on one model
   may silently do nothing on another. This makes Ubuntu packaging (where users expect
   it to just work) high-risk to maintain.

3. **DKMS complexity**: Some features (AuraSync, certain fan controllers) need out-of-tree
   kernel modules. Ubuntu's LTS kernel moves slower than Fedora's, creating version drift.

4. **Community fragmentation**: ASUS users on Linux are a minority of a minority. Most
   Linux laptop users have ThinkPads, Frameworks, or MacBooks with better native support.
   The ASUS Linux community exists but is small and primarily Fedora/Arch.

5. **The repo IS maintained** — this is not an abandoned project. The gap is specifically
   Ubuntu/Debian packaging + maintenance, not development.

---

## What a Ubuntu/Debian Fork Would Need to Do

### Packaging (first milestone)
- Write `debian/` control files for `asusd`, `supergfxd`, `asusctl` CLI
- Handle systemd unit installation correctly for Ubuntu's systemd layout
- Ship udev rules for device access without root
- Ship dbus policy files for the session bus interface
- PPA on Launchpad for Ubuntu 22.04 (Jammy) and 24.04 (Noble)

### Ubuntu-specific fixes
- Ubuntu uses `gdm3` not `sddm` — GPU mode switch needs to handle display manager restart
  correctly for GDM
- `nvidia-prime` integration — Ubuntu already has prime-select; supergfxctl needs to
  coexist rather than conflict
- AppArmor profiles — Ubuntu ships AppArmor by default; the dbus daemon needs profiles

### Nice to have (second milestone)
- GNOME Shell extension for quick access (thermal profile toggle in top bar, GPU mode)
- GUI wrapper (GTK4 or libadwaita) — Armoury Crate equivalent, minimal

---

## Collaboration Path

**Option A: Contribute Ubuntu packaging upstream**
- Open issue on gitlab.com/asus-linux/asusctl proposing a Debian branch
- Offer to maintain the PPA
- They are open to contributions — the gap is volunteer time, not intent

**Option B: Fork and maintain independently**
- Fork to github.com/Baraka-Malila/asusctl-ubuntu (or similar)
- Add CI for Ubuntu targets
- Publish PPA, document the Ubuntu-specific setup

**Option C: Just the packaging layer**
- Write a separate `asus-ubuntu-setup` tool that:
  - Installs the upstream binaries (pre-compiled Rust)
  - Handles Ubuntu-specific config (dbus, AppArmor, nvidia-prime integration)
  - Ships as a single `.deb` or install script
  - This avoids forking the Rust codebase while solving the packaging problem

Option C is lowest effort and highest immediate impact. Most users just need it to install
cleanly; the upstream code is already good.

---

## Technical Entry Points

```bash
# The kernel interface everything uses
ls /sys/devices/platform/asus-nb-wmi/

# Current thermal policy (0=performance, 1=balanced, 2=silent)
cat /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy

# Fan speed sensors
cat /sys/class/hwmon/hwmon*/fan*_input 2>/dev/null

# Battery charge limit (if supported by this model)
cat /sys/class/power_supply/BAT0/charge_control_end_threshold 2>/dev/null

# asusctl source
# git clone https://gitlab.com/asus-linux/asusctl.git
# cargo build --release

# supergfxctl source  
# git clone https://gitlab.com/asus-linux/supergfxctl.git
```

---

## Hardware Profile (FA507NV)

- **CPU:** AMD Ryzen (Zen 4 or Zen 3+, confirm with `lscpu`)
- **GPU:** RTX 4060 Laptop (Ada Lovelace, PCIe 4.0 x8) + AMD iGPU
- **Display:** driven by AMD iGPU (NVIDIA in Optimus/render offload mode)
- **Fans:** 2 fans, accessible via WMI
- **RGB:** keyboard backlight (no per-key RGB on TUF models, just brightness)
- **Battery threshold:** check if `charge_control_end_threshold` exists for this model
- **WMI features confirmed working on Ubuntu:** thermal policy, basic fan speed read

---

## Why This Is Worth Building

ASUS TUF Gaming is one of the most common mid-range gaming laptops worldwide.
It's affordable, well-specced, and widely used by students and developers in markets
where premium ThinkPads and Frameworks are too expensive (East Africa, South/Southeast Asia,
Latin America). These are exactly the regions where Ubuntu is the dominant Linux distribution.
The users who most need this tool are the users least served by the current Fedora-only solution.

---

*Created: 2026-06-20*  
*Author: Baraka Malila*  
*Next step: Check Option C feasibility — inspect asusctl release binaries for portability*
