# Phase 3 — utu GUI Design Spec

**Date:** 2026-07-04  
**Scope:** Fork Ayuz → adapt for Ubuntu/GNOME → package as `utu` → ship via `asus-suite`  
**Target distro:** Ubuntu 24.04 Noble only (GTK 4.14 ✓ / libadwaita 1.5 — see Section 5e)  
**Long-term goal:** Full C-level rebranding + Flathub distribution after v0.1 ships

---

## 1. What We Are Building

`utu` is a GTK4/libadwaita ASUS laptop control centre for Ubuntu. It forks
Ayuz (github.com/Traciges/Ayuz, GPL-3.0) and adapts it for Ubuntu/GNOME,
adds an Armoury Crate key handler, and packages it as part of the
`asus-suite` meta-package so users get the full stack with one command:

```
sudo add-apt-repository ppa:malila-arch/asusctl-ubuntu
sudo apt install asus-suite
```

`utu` sits on top of `asusd` and `supergfxd` and communicates exclusively
over D-Bus — no root process, no direct sysfs writes.

---

## 2. Naming & Branding

| Layer | Name | Rationale |
|---|---|---|
| Product brand | `utu` | Swahili "humaneness", Ubuntu root, trademark-safe |
| GUI package | `utu` | Debian package name in the PPA |
| Meta-package | `asus-suite` | Replaces `asusctl-suite`, discoverable via `apt search asus` |
| Window title | `Utu — ASUS Laptop Control` | Clear to users sitting in front of it |
| Application ID | `io.github.baraka_malila.utu` | Reverse-domain, our GitHub |
| Repo | `github.com/Baraka-Malila/utu` | Separate from packaging repo |

Ayuz attribution: Guido Philipp's copyright headers are preserved in all
forked files. The about dialog credits Ayuz as upstream. README explains
the fork relationship.

---

## 3. Architecture

```
┌─────────────────────────────────────────────┐
│                  utu (GUI)                  │
│   relm4 0.10 + libadwaita 0.8 + zbus 5     │
│   Runs as logged-in user, Noble only        │
└──────────────┬──────────────────────────────┘
               │ D-Bus (system bus)
      ┌────────┴──────────┐
      │   asusd daemon    │  ← asusctl package
      │  supergfxd daemon │  ← supergfxctl package
      └───────────────────┘
               │
      ┌────────┴──────────┐
      │  asus-nb-wmi      │  kernel module (built-in on Ubuntu)
      │  evdev hotkeys    │  Armoury Crate key, fan key
      └───────────────────┘
```

`utu` runs persistently in the system tray after login (Ayuz's existing
behaviour: window hides to tray on close, process stays alive). This
means the Armoury Crate key can always reach a running instance.

---

## 4. Repository Structure

New repo `github.com/Baraka-Malila/utu`, forked from Ayuz:

```
utu/
├── src/
│   ├── main.rs
│   ├── app.rs
│   ├── components/        # GPU, fan, keyboard, battery, audio, display, Aura, system
│   ├── services/
│   │   ├── armoury_key.rs # NEW — Armoury Crate button handler
│   │   ├── dbus.rs        # zbus D-Bus proxies (unchanged from Ayuz)
│   │   ├── fan_hotkey.rs  # unchanged
│   │   └── ...
│   └── ...
├── locales/               # en.yml updated: "Ayuz" → "Utu" throughout
├── assets/                # style.css kept; icon replaced with utu icon
├── debian/                # packaging lives in the utu repo
│   ├── control
│   ├── changelog          # utu 0.1.0~noble1
│   ├── rules
│   ├── copyright          # GPL-3.0, credits Guido Philipp
│   └── utu.desktop
├── Cargo.toml             # name = "utu", app-id updated
├── LICENSE                # GPL-3.0 preserved
└── README.md              # attributes Ayuz; explains Ubuntu adaptation
```

---

## 5. Changes From Ayuz

### 5a. Strip (KDE/Fedora-specific)

| File | Action |
|---|---|
| `src/services/kde_brightness.rs` | Replace with GNOME brightness via `org.gnome.SettingsDaemon.Power.Screen` D-Bus |
| Any `swayidle` / `kscreen-doctor` calls | Remove — GNOME handles idle natively |

### 5b. Rename (everywhere)

- `locales/en.yml` and all locale files: `"Ayuz"` → `"Utu"`
- `Cargo.toml`: `name = "ayuz"` → `name = "utu"`
- `src/main.rs`: `RelmApp::new("de.guido.ayuz")` → `RelmApp::new("io.github.baraka_malila.utu")`
- Tray tooltip, desktop entry, about dialog — all updated to Utu branding

### 5c. Add (Ubuntu-specific)

**Armoury Crate key** (`src/services/armoury_key.rs`):
- Same evdev pattern as `fan_hotkey.rs`
- Listens for `KEY_PROG1` (keycode 148) on the `Asus WMI hotkeys` evdev node
- On press: calls `window.present()` to show/focus the utu window
- Falls back to any keyboard device advertising keycode 148

**GDM3 restart prompt** (in `src/components/system/gpu.rs`):
- After a successful `SetMode` D-Bus call, show an `adw::AlertDialog`
- Message: *"GPU mode changed. Restart the display server now to apply it?"*
- Actions: "Restart Now" → `systemctl restart gdm3` | "Later" → dismiss
- Replaces Ayuz's passive "reboot required" label

**About dialog** (`src/components/`):
- Utu version, GitHub link, GPL-3.0 licence
- Credits: "Built on Ayuz by Guido Philipp (github.com/Traciges/Ayuz)"

### 5e. libadwaita Version Adaptation

Noble ships libadwaita **1.5.0**. Ayuz declares `features = ["v1_8"]` in
`Cargo.toml`, which requires libadwaita 1.8 headers to compile.

Approach: lower the feature flag to `v1_5` in our fork and audit the
codebase for any widgets or APIs introduced after 1.5
(`adw::OverlaySplitView`, `adw::BreakpointBin`, `adw::Spinner`, etc.).
Replace any 1.6+ widgets with 1.5 equivalents. The core widgets Ayuz
visibly uses (`adw::ComboRow`, `adw::PreferencesGroup`,
`adw::NavigationPage`, `adw::ApplicationWindow`) all exist in 1.5 — the
delta is expected to be small.

If lowering to `v1_5` breaks significant UI patterns, the fallback is to
add the GNOME Team PPA (`ppa:gnome-team/gnome`) which ships libadwaita 1.7+
on Noble, but this adds a user-facing dependency and is the less preferred
path.

This audit is Task 1 of the implementation plan.

### 5f. Keep Unchanged

All existing Ayuz components work correctly on GNOME/Ubuntu:
- GPU switching (supergfxctl D-Bus) ✓
- Power profiles (asusctl D-Bus) ✓
- Keyboard backlight ✓
- Battery charge limit ✓
- Aura RGB (greyed on TUF — hardware detection works) ✓
- AniMatrix / NumberPad (greyed on TUF) ✓
- Audio, display, touchpad ✓
- Profiles system, autostart, search ✓
- `ksni` tray — StatusNotifierItem works on Ubuntu GNOME with AppIndicator ✓

---

## 6. Packaging

### 6a. utu debian/ package

- Binary: `/usr/bin/utu`
- Desktop entry: `/usr/share/applications/io.github.baraka_malila.utu.desktop`
- Icon: `/usr/share/icons/hicolor/scalable/apps/io.github.baraka_malila.utu.svg`
- Build deps: `cargo`, `libgtk-4-dev (>= 4.14)`, `libadwaita-1-dev (>= 1.5)`, `libdbus-1-dev`
- Runtime deps: `asusctl`, `supergfxctl`, `libadwaita-1-0 (>= 1.5)`
- Noble-only: `debian/changelog` targets `noble` only, no jammy entry

### 6b. asus-suite meta-package (renamed from asusctl-suite)

```
Package: asus-suite
Depends: asusctl, supergfxctl, asus-backlight-fix, utu [amd64 noble]
```

On Noble: installs all four including GUI.  
On Jammy: `utu` dependency is architecture/distro-conditional — CLI tools
install, GUI is omitted with a note recommending Noble upgrade.

### 6c. asusctl-ubuntu packaging repo changes

- New `packages/utu/` directory pointing to `utu` repo as upstream
- `packages/asus-suite/debian/control` updated with `utu` dependency
- CI gains a Noble-only job that builds `utu.deb`
- `scripts/upload-ppa.sh` loop updated to include `utu`

---

## 7. OS Requirement

`utu` requires Ubuntu 24.04 Noble. The user's current machine runs Jammy
(22.04). An in-place LTS upgrade (`do-release-upgrade`) is required before
implementation can be tested on hardware. This upgrade runs as a separate
step at the start of Phase 3 implementation, before any code is written.

Key risks to manage during upgrade:
- NVIDIA 580.x driver: verify re-installation after upgrade
- Kernel cmdline (`acpi_osi=Linux acpi_backlight=native nvidia_drm.modeset=1 pcie_aspm=off`): verify preserved in `/etc/default/grub`
- PPA disabled automatically: re-enable after upgrade
- bongoSTEM at `~/bongoSTEM`: unaffected (separate directory)

---

## 8. Long-Term Distribution (Post v0.1, Phase 4)

After Phase 3 ships and Phase C rebranding is done:

1. **Flathub (Flatpak)** — primary path to non-Ubuntu users (Arch, Fedora,
   Debian, Pop!\_OS). Requires a Flatpak manifest with:
   - `--system-talk-name=xyz.ljones.*` (asusd)
   - `--system-talk-name=org.supergfxctl.*` (supergfxd)
   - `--device=all` or specific evdev node access (hotkeys)
2. **GitHub Releases** — attach `.deb` artifacts for direct download
3. **Snap** — lower priority; evdev + system D-Bus sandbox is harder than Flatpak

---

## 9. What This Phase Does NOT Include

- C-level rebranding (custom navigation design, hardware illustrations, welcome screen) — Phase 4
- Flatpak manifest — Phase 4
- Snap packaging — Phase 4
- AppArmor profiles for utu — can be added in Phase 3 or 4
- Jammy GTK4 backport — not planned
