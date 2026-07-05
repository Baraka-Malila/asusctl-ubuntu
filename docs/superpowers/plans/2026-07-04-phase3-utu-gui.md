# Phase 3 — utu GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fork Ayuz into a new `utu` repo, adapt it for Ubuntu/GNOME, add an Armoury Crate key handler and GDM3 restart prompt, then package it into the PPA as part of `asus-suite`.

**Architecture:** `utu` is a relm4/libadwaita GUI that talks to `asusd` and `supergfxd` over D-Bus. It runs as the logged-in user. The source lives in a separate repo (`~/utu/`); Debian packaging lives in `~/asus/packages/utu/`. The PPA meta-package `asus-suite` gains `utu` as a dependency so `apt install asus-suite` delivers the full stack.

**Tech Stack:** Rust (edition 2024, toolchain 1.85+ via rustup), relm4 0.10, libadwaita 0.8 (`v1_5` feature), GTK4 0.10 (`v4_14` feature), zbus 5, evdev 0.13, tokio 1.

## Global Constraints

- Noble (Ubuntu 24.04) only — libadwaita 1.5 and GTK 4.14 are Noble minimums
- libadwaita feature pinned to `v1_5` (Noble ships 1.5.0; Ayuz upstream uses `v1_8` — we lower it)
- Rust toolchain: 1.85+ (required for edition 2024); install via rustup, not apt
- GPL-3.0 licence preserved; Guido Philipp copyright headers kept in all forked files
- Application ID: `io.github.baraka_malila.utu`
- Source repo: `~/utu/` (sibling to `~/asus/`)
- Packaging repo: `~/asus/packages/utu/`
- 300-line file limit (code files); split proactively at 250
- Never commit compiled binaries or `target/`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `~/utu/` | Create (fork) | New source repo |
| `~/utu/Cargo.toml` | Modify | Rename to `utu`, lower libadwaita to `v1_5` |
| `~/utu/src/main.rs` | Modify | App ID, prgname, socket name |
| `~/utu/src/tray.rs` | Modify | Rename `AyuzTray` → `UtuTray` |
| `~/utu/src/app.rs` | Modify | Rename tray ref, spawn armoury key service |
| `~/utu/src/services/mod.rs` | Modify | Swap `kde_brightness` → `gnome_brightness`, add `armoury_key` |
| `~/utu/src/services/kde_brightness.rs` | Delete | Replaced |
| `~/utu/src/services/gnome_brightness.rs` | Create | GNOME SettingsDaemon brightness proxy |
| `~/utu/src/services/armoury_key.rs` | Create | evdev listener for KEY\_PROG1 (keycode 148) |
| `~/utu/src/services/edge_gestures.rs` | Modify | Update brightness import |
| `~/utu/src/components/display/oled_dimming.rs` | Modify | Update brightness import |
| `~/utu/src/components/system/gpu.rs` | Modify | GDM3 restart AlertDialog |
| `~/utu/locales/en.yml` | Modify | `"Ayuz"` → `"Utu"`, add new locale keys |
| `~/utu/locales/de.yml` | Modify | Same rename |
| `~/utu/locales/pt-br.yml` | Modify | Same rename |
| `~/utu/README.md` | Modify | Utu branding, Ayuz attribution |
| `~/utu/debian/control` | Create | Package metadata |
| `~/utu/debian/changelog` | Create | `utu (0.1.0~noble1)` |
| `~/utu/debian/rules` | Create | `cargo build --release --offline` |
| `~/utu/debian/copyright` | Create | GPL-3.0, credits Guido Philipp |
| `~/utu/debian/utu.desktop` | Create | Desktop entry |
| `~/asus/packages/utu/upstream.env` | Create | Points to GitHub release tarball |
| `~/asus/packages/utu/debian/` | Create | Copy of `~/utu/debian/` (PPA authoritative copy) |
| `~/asus/packages/asus-suite/debian/control` | Modify | Add `utu` dependency |
| `~/asus/.github/workflows/build-debs.yml` | Modify | Add `utu` Noble-only build job |

---

## Task 1: Upgrade to Noble (Ubuntu 24.04)

> This task is purely operational. No code is written. It must complete before any task that involves running or testing the GUI. Tasks 2-4 coding steps can start before this, but all verification steps require Noble.

**Files:** none  
**Interfaces:** none

- [ ] **Step 1: Capture current state**

```bash
cat /etc/os-release | grep VERSION
cat /etc/default/grub | grep GRUB_CMDLINE
cat /etc/modprobe.d/nvidia-custom.conf
dpkg -l | grep nvidia | grep -v "^rc"
```

Save this output somewhere safe (screenshot or paste to a text file).

- [ ] **Step 2: Verify enough disk space**

```bash
df -h /
```

Need at least 5 GB free. The upgrade downloads ~2 GB.

- [ ] **Step 3: Disable all PPAs (upgrade will do this anyway, but confirm)**

```bash
sudo add-apt-repository --remove ppa:malila-arch/asusctl-ubuntu
```

- [ ] **Step 4: Run the upgrade**

```bash
sudo do-release-upgrade
```

Follow the interactive prompts. When asked about config files, keep the current version (`N` or `keep current`). When asked to restart services, say yes. The upgrade takes 20-60 minutes depending on network.

- [ ] **Step 5: Reboot**

```bash
sudo reboot
```

- [ ] **Step 6: Verify Noble is running**

```bash
cat /etc/os-release | grep VERSION
# Expected: VERSION="24.04.x LTS (Noble Numbat)"
uname -r
# Expected: 6.8.x-generic or newer
```

- [ ] **Step 7: Verify NVIDIA driver**

```bash
nvidia-smi | head -5
# Expected: shows GPU name (NVIDIA GeForce RTX 4060 Laptop) and driver version
nvidia-settings --version
```

If NVIDIA driver is missing: `sudo apt install nvidia-driver-535` (or the current recommended version for Noble).

- [ ] **Step 8: Verify kernel cmdline preserved**

```bash
cat /proc/cmdline
# Must contain: acpi_osi=Linux acpi_backlight=native nvidia_drm.modeset=1 pcie_aspm=off
```

If missing: edit `/etc/default/grub`, add them back to `GRUB_CMDLINE_LINUX_DEFAULT`, run `sudo update-grub`, reboot.

- [ ] **Step 9: Verify modprobe config preserved**

```bash
cat /etc/modprobe.d/nvidia-custom.conf
# Must still contain the 4 NVIDIA options from before the upgrade
```

- [ ] **Step 10: Re-enable PPA and verify packages**

```bash
sudo add-apt-repository ppa:malila-arch/asusctl-ubuntu
sudo apt update
sudo apt install asusctl supergfxctl asus-backlight-fix
asusctl --version
supergfxctl --version
```

- [ ] **Step 11: Verify build tools on Noble**

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain 1.85.0 -y
source ~/.cargo/env
rustc --version   # must be 1.85.x
cargo --version
sudo apt install -y libgtk-4-dev libadwaita-1-dev libdbus-1-dev libevdev-dev pkg-config
```

- [ ] **Step 12: Verify libadwaita version**

```bash
pkg-config --modversion libadwaita-1
# Expected: 1.5.x
```

---

## Task 2: Fork and Rename to utu

**Files:**
- Create: `~/utu/` (forked repo)
- Modify: `~/utu/Cargo.toml`
- Modify: `~/utu/src/main.rs`
- Modify: `~/utu/src/tray.rs`
- Modify: `~/utu/src/app.rs` (tray ref only, armoury key added in Task 5)
- Modify: `~/utu/locales/en.yml`, `de.yml`, `pt-br.yml`
- Modify: `~/utu/README.md`

**Interfaces:**
- Produces: buildable `utu` binary (used by all subsequent tasks)

- [ ] **Step 1: Fork Ayuz on GitHub**

Go to `https://github.com/Traciges/Ayuz` → Fork → Repository name: `utu` → Owner: `Baraka-Malila`. Uncheck "Copy the main branch only" is fine (keep default).

- [ ] **Step 2: Clone locally**

```bash
cd ~
git clone https://github.com/Baraka-Malila/utu.git
cd utu
```

- [ ] **Step 3: Update Cargo.toml — name, app description, libadwaita version**

Open `~/utu/Cargo.toml`. Make these exact changes:

```toml
# Change:
name = "ayuz"
# To:
name = "utu"

# Change:
description = "Unofficial MyAsus Clone for Asus Laptops"
# To:
description = "ASUS laptop control centre for Ubuntu"

# Change (in [dependencies]):
libadwaita = { version = "0.8", features = ["v1_8"] }
# To:
libadwaita = { version = "0.8", features = ["v1_5"] }
```

- [ ] **Step 4: Update main.rs — app ID, prgname, socket name**

In `~/utu/src/main.rs`, make these exact replacements:

```rust
// Change:
gtk4::glib::set_prgname(Some("de.guido.ayuz"));
// To:
gtk4::glib::set_prgname(Some("io.github.baraka_malila.utu"));

// Change:
let a = relm4::RelmApp::new("de.guido.ayuz").with_args(gtk_args);
// To:
let a = relm4::RelmApp::new("io.github.baraka_malila.utu").with_args(gtk_args);

// Change (two occurrences — in main() and in the CLI --toggle-numberpad path):
abstract_socket_addr("ayuz-numberpad")
// To:
abstract_socket_addr("utu-numberpad")
```

- [ ] **Step 5: Rename AyuzTray → UtuTray in tray.rs**

```bash
sed -i 's/AyuzTray/UtuTray/g' ~/utu/src/tray.rs
```

- [ ] **Step 6: Update app.rs tray reference**

```bash
sed -i 's/AyuzTray/UtuTray/g' ~/utu/src/app.rs
sed -i 's/ayuz-numberpad/utu-numberpad/g' ~/utu/src/app.rs
```

- [ ] **Step 7: Update locale strings**

```bash
# en.yml
sed -i 's/app_title: "Ayuz"/app_title: "Utu"/' ~/utu/locales/en.yml
# Add new keys needed by Task 6 (GDM3 dialog) at the end of en.yml:
cat >> ~/utu/locales/en.yml << 'EOF'
gpu_restart_title: "Restart Display Server?"
gpu_restart_body: "The GPU mode has changed. Restarting GDM3 will log you out and apply the new mode immediately."
gpu_restart_now: "Restart Now"
gpu_restart_later: "Later"
EOF

# de.yml and pt-br.yml — use English fallback for now, just rename app_title
sed -i 's/app_title: "Ayuz"/app_title: "Utu"/' ~/utu/locales/de.yml
sed -i 's/app_title: "Ayuz"/app_title: "Utu"/' ~/utu/locales/pt-br.yml
```

- [ ] **Step 8: Update README.md**

Replace the first section of `~/utu/README.md` with:

```markdown
# Utu — ASUS Laptop Control for Ubuntu

A GTK4/libadwaita control centre for ASUS laptops on Ubuntu 24.04 (Noble).

Utu is a fork of [Ayuz](https://github.com/Traciges/Ayuz) by Guido Philipp,
adapted for Ubuntu/GNOME with an Armoury Crate key handler and GDM3
display-server restart support. Ayuz copyright headers are preserved in all
forked source files per the GPL-3.0 licence.

**Tested on:** ASUS TUF Gaming A15 FA507NV · Ubuntu 24.04 · GNOME
```

- [ ] **Step 9: Attempt first build (expect libadwaita failures)**

```bash
cd ~/utu
cargo check 2>&1 | head -40
```

If the only errors are missing libadwaita `v1_8` APIs — proceed to Task 3. If there are other errors, fix them before continuing.

- [ ] **Step 10: Commit**

```bash
cd ~/utu
git add -A
git commit -m "fork: rename Ayuz → utu, update app-id and locale strings"
```

---

## Task 3: libadwaita 1.5 Compatibility

**Files:**
- Modify: `~/utu/Cargo.toml` (already done in Task 2 Step 3)
- Modify: any files that call libadwaita 1.6+ APIs

**Interfaces:**
- Produces: `cargo build` succeeds on Noble (libadwaita 1.5)

- [ ] **Step 1: Run cargo check and capture all errors**

```bash
cd ~/utu
cargo check 2>&1 | grep "^error" | sort -u
```

- [ ] **Step 2: Fix each compilation error**

Common libadwaita 1.6+ APIs that may appear and their 1.5 replacements:

| 1.6+ API | 1.5 replacement |
|---|---|
| `adw::OverlaySplitView` | `adw::Leaflet` or `gtk4::Paned` |
| `adw::BreakpointBin` | Remove or use fixed layout |
| `adw::AlertDialog` | Available in 1.5 — keep as-is |
| `adw::SpinnerPaintable` | `gtk4::Spinner` widget |

For each error: read the error, find the file, apply the replacement. Commit after each fixed file.

```bash
# After fixing each file:
cargo check 2>&1 | grep "^error" | wc -l   # count remaining errors
```

- [ ] **Step 3: Verify full build succeeds**

```bash
cd ~/utu
cargo build 2>&1 | tail -5
# Expected: "Finished dev [unoptimized + debuginfo] target(s) in Xs"
```

- [ ] **Step 4: Verify binary launches (visual check)**

```bash
cd ~/utu
DISPLAY=:0 cargo run 2>/dev/null &
sleep 3
# Expected: utu window appears with GNOME libadwaita styling
kill %1
```

- [ ] **Step 5: Commit**

```bash
cd ~/utu
git add -A
git commit -m "port: lower libadwaita requirement to v1_5 for Noble compatibility"
```

---

## Task 4: Strip KDE Services, Add GNOME Brightness

**Files:**
- Create: `~/utu/src/services/gnome_brightness.rs`
- Delete: `~/utu/src/services/kde_brightness.rs`
- Modify: `~/utu/src/services/mod.rs`
- Modify: `~/utu/src/services/edge_gestures.rs`
- Modify: `~/utu/src/components/display/oled_dimming.rs`

**Interfaces:**
- Produces: `gnome_brightness::adjust_brightness_relative(delta: i32)` (same signature as the KDE version it replaces)
- Produces: `gnome_brightness::GnomeBrightnessControlProxy` (used by `oled_dimming.rs`)

- [ ] **Step 1: Create gnome_brightness.rs**

Create `~/utu/src/services/gnome_brightness.rs` with this full content:

```rust
// Utu — ASUS Laptop Control for Ubuntu (fork of Ayuz by Guido Philipp)
// SPDX-License-Identifier: GPL-3.0-or-later

/// D-Bus proxy for GNOME SettingsDaemon screen brightness.
/// Replaces the KDE PowerDevil proxy from the upstream Ayuz project.
#[zbus::proxy(
    interface = "org.gnome.SettingsDaemon.Power.Screen",
    default_service = "org.gnome.SettingsDaemon",
    default_path = "/org/gnome/SettingsDaemon/Power"
)]
pub trait GnomeBrightnessControl {
    #[zbus(property, name = "Brightness")]
    fn brightness(&self) -> zbus::Result<i32>;

    #[zbus(property, name = "Brightness")]
    fn set_brightness(&self, value: i32) -> zbus::Result<()>;
}

/// Returns the current brightness (0–100). Returns `Err` if
/// GNOME SettingsDaemon is not running (e.g. non-GNOME session).
pub async fn get_brightness() -> Result<i32, String> {
    let conn = zbus::Connection::session().await.map_err(|e| e.to_string())?;
    let proxy = GnomeBrightnessControlProxy::new(&conn)
        .await
        .map_err(|e| e.to_string())?;
    proxy.brightness().await.map_err(|e| e.to_string())
}

/// Adjusts screen brightness by `delta_percent` (e.g. +5 or -5), clamped
/// to 1–100. Returns `Err` if GNOME SettingsDaemon is unreachable.
pub async fn adjust_brightness_relative(delta_percent: i32) -> Result<(), String> {
    let conn = zbus::Connection::session().await.map_err(|e| e.to_string())?;
    let proxy = GnomeBrightnessControlProxy::new(&conn)
        .await
        .map_err(|e| e.to_string())?;
    let cur = proxy.brightness().await.map_err(|e| e.to_string())?;
    let next = (cur + delta_percent).clamp(1, 100);
    proxy.set_brightness(next).await.map_err(|e| e.to_string())
}

/// Returns 100 — GNOME uses a 0–100 scale so the max is always 100.
/// Provided for API compatibility with callers that previously asked KDE
/// for a variable `brightness_max`.
pub fn brightness_max() -> i32 {
    100
}
```

- [ ] **Step 2: Update services/mod.rs**

In `~/utu/src/services/mod.rs`:

```rust
// Remove:
pub mod kde_brightness;
// Add:
pub mod gnome_brightness;
// Add (new module, added in Task 5):
pub mod armoury_key;
```

- [ ] **Step 3: Update edge_gestures.rs import**

In `~/utu/src/services/edge_gestures.rs`:

```rust
// Change:
use crate::services::kde_brightness;
// To:
use crate::services::gnome_brightness;

// Change (all occurrences of kde_brightness::):
kde_brightness::adjust_brightness_relative(delta).await
// To:
gnome_brightness::adjust_brightness_relative(delta).await
```

- [ ] **Step 4: Update oled_dimming.rs import**

In `~/utu/src/components/display/oled_dimming.rs`:

```rust
// Change:
use crate::services::kde_brightness::BrightnessControlProxy;
// To:
use crate::services::gnome_brightness::GnomeBrightnessControlProxy;
```

Then replace all uses of `BrightnessControlProxy` with `GnomeBrightnessControlProxy` in that file:

```bash
sed -i 's/BrightnessControlProxy/GnomeBrightnessControlProxy/g' \
    ~/utu/src/components/display/oled_dimming.rs
```

- [ ] **Step 5: Delete kde_brightness.rs**

```bash
rm ~/utu/src/services/kde_brightness.rs
git rm ~/utu/src/services/kde_brightness.rs
```

- [ ] **Step 6: Remove is_kde_desktop dependency in oled_dimming.rs**

Search `oled_dimming.rs` for `is_kde_desktop` and remove it — the GNOME proxy will return `Err` gracefully on non-GNOME sessions, making the explicit KDE check unnecessary.

```bash
grep -n "is_kde_desktop\|kde_available" ~/utu/src/components/display/oled_dimming.rs
```

For each occurrence: remove the `is_kde_desktop()` call and the `kde_available` field/check. The component can gate on whether `get_brightness()` returns `Ok` instead.

- [ ] **Step 7: Verify build**

```bash
cd ~/utu && cargo check 2>&1 | grep "^error"
# Expected: no output (zero errors)
```

- [ ] **Step 8: Check for remaining swayidle / kscreen-doctor references**

```bash
grep -rn "swayidle\|kscreen-doctor\|kscreen_doctor" ~/utu/src/ --include="*.rs"
```

For each hit: remove the call. These are KDE/Wayland compositor tools with no GNOME equivalent. The functionality they provided (idle-based backlight dimming on KDE) is handled natively by GNOME's power settings.

- [ ] **Step 9: Check for any remaining Ayuz identity strings**

```bash
grep -rn "Ayuz\|ayuz\|de\.guido" ~/utu/src/ --include="*.rs"
```

For each hit not inside a GPL copyright header: rename to `utu` / `Utu` / `io.github.baraka_malila.utu` as appropriate.

- [ ] **Step 10: Commit**

```bash
cd ~/utu
git add -A
git commit -m "adapt: replace KDE brightness D-Bus with GNOME SettingsDaemon"
```

---

## Task 5: Armoury Crate Key Handler

**Files:**
- Create: `~/utu/src/services/armoury_key.rs`
- Modify: `~/utu/src/services/mod.rs` (add `pub mod armoury_key;` — already noted in Task 4 Step 2)
- Modify: `~/utu/src/app.rs` (spawn the service)

**Interfaces:**
- Consumes: `AppMsg::ShowWindow` (already exists in `app.rs` — raises and focuses window)
- Consumes: `crate::services::evdev_runner::open_event_stream(device: Device) -> Option<EventStream>`
- Produces: `armoury_key::run(sender: relm4::Sender<AppMsg>)` — async, long-running

- [ ] **Step 1: Create armoury_key.rs**

Create `~/utu/src/services/armoury_key.rs` with this full content:

```rust
// Utu — ASUS Laptop Control for Ubuntu (fork of Ayuz by Guido Philipp)
// SPDX-License-Identifier: GPL-3.0-or-later

use evdev::{Device, EventSummary, KeyCode};

use crate::app::AppMsg;
use crate::services::evdev_runner::open_event_stream;

/// KEY_PROG1 (148) — the physical Armoury Crate button on ASUS laptops.
/// Emitted by asus-nb-wmi via the `Asus WMI hotkeys` evdev node.
const ARMOURY_KEYCODES: &[u16] = &[148];

fn find_armoury_device() -> Option<Device> {
    let mut fallback: Option<Device> = None;

    for (_, device) in evdev::enumerate() {
        let name = device.name().unwrap_or_default().to_lowercase();
        let is_asus = name.contains("asus") && (name.contains("wmi") || name.contains("hotkey"));

        if let Some(keys) = device.supported_keys() {
            let has_key = ARMOURY_KEYCODES.iter().any(|&c| keys.contains(KeyCode::new(c)));
            if is_asus && has_key {
                return Some(device);
            }
            if has_key && fallback.is_none() {
                fallback = Some(device);
            }
        }
    }
    fallback
}

/// Watches the Armoury Crate button and emits [`AppMsg::ShowWindow`] on each
/// press. Returns immediately if no device advertising the key is found.
pub async fn run(sender: relm4::Sender<AppMsg>) {
    let Some(device) = find_armoury_device() else {
        tracing::info!("armoury_key: no device found — Armoury Crate key unavailable");
        return;
    };

    if let Some(name) = device.name() {
        tracing::info!("armoury_key: listening on {name}");
    }

    let Some(mut stream) = open_event_stream(device) else {
        return;
    };

    loop {
        let event = match stream.next_event().await {
            Ok(ev) => ev,
            Err(e) => {
                tracing::warn!("armoury_key: event read error: {e}");
                break;
            }
        };

        if let EventSummary::Key(_, key, 1) = event.destructure() {
            if ARMOURY_KEYCODES.contains(&key.code()) {
                sender.emit(AppMsg::ShowWindow);
            }
        }
    }
}
```

- [ ] **Step 2: Spawn armoury_key service in app.rs**

In `~/utu/src/app.rs`, find the block where `fan_hotkey` is spawned:

```rust
tokio::spawn(crate::services::fan_hotkey::run(fan_sender, fan_hotkey_rx));
```

Add immediately after it:

```rust
let armoury_sender = sender.input_sender().clone();
tokio::spawn(crate::services::armoury_key::run(armoury_sender));
```

- [ ] **Step 3: Verify build**

```bash
cd ~/utu && cargo check 2>&1 | grep "^error"
# Expected: no output
```

- [ ] **Step 4: Run and test Armoury Crate key (requires Noble + hardware)**

```bash
cd ~/utu && cargo run &
sleep 3
# Close the utu window (it goes to tray)
# Press the physical Armoury Crate button on the laptop
# Expected: utu window appears/raises
kill %1
```

- [ ] **Step 5: Commit**

```bash
cd ~/utu
git add src/services/armoury_key.rs src/services/mod.rs src/app.rs
git commit -m "feat: Armoury Crate key handler — KEY_PROG1 raises utu window"
```

---

## Task 6: GDM3 Restart Prompt After GPU Mode Change

**Files:**
- Modify: `~/utu/src/components/system/gpu.rs`
- (locale keys already added in Task 2 Step 7)

**Interfaces:**
- Consumes: `adw::AlertDialog` (libadwaita 1.5+), `adw::ResponseAppearance`
- Consumes: `AppMsg` output from `GpuModel` (already wired as `String` error channel)

- [ ] **Step 1: Add GDM3 restart dialog to gpu.rs**

In `~/utu/src/components/system/gpu.rs`, find the `ModeSet` arm inside `update_cmd`:

```rust
GpuCommandOutput::ModeSet(mode) => {
    tracing::info!(
        "{}",
        t!("gpu_mode_set", mode = t!(mode.i18n_key()).to_string())
    );
}
```

Replace it with:

```rust
GpuCommandOutput::ModeSet(mode) => {
    tracing::info!(
        "{}",
        t!("gpu_mode_set", mode = t!(mode.i18n_key()).to_string())
    );
    let dialog = adw::AlertDialog::new(
        Some(&t!("gpu_restart_title")),
        Some(&t!("gpu_restart_body")),
    );
    dialog.add_response("later", &t!("gpu_restart_later"));
    dialog.add_response("now", &t!("gpu_restart_now"));
    dialog.set_response_appearance("now", adw::ResponseAppearance::Suggested);
    dialog.set_default_response(Some("later"));
    dialog.set_close_response("later");
    dialog.connect_response(None, |_, response| {
        if response == "now" {
            let _ = std::process::Command::new("pkexec")
                .args(["systemctl", "restart", "gdm3"])
                .spawn();
        }
    });
    dialog.present(Some(root));
}
```

- [ ] **Step 2: Verify build**

```bash
cd ~/utu && cargo check 2>&1 | grep "^error"
# Expected: no output
```

- [ ] **Step 3: Test the dialog (requires Noble + hardware)**

```bash
cd ~/utu && cargo run &
sleep 3
# In the utu window: System → GPU → change mode (e.g. Hybrid → Integrated)
# Expected: AlertDialog appears with "Restart Now" and "Later" buttons
# Click "Later" — dialog closes, no restart
# Change mode again, click "Restart Now" — polkit prompt appears, then GDM3 restarts
kill %1   # if you clicked Later
```

- [ ] **Step 4: Commit**

```bash
cd ~/utu
git add src/components/system/gpu.rs
git commit -m "feat: GDM3 restart prompt after GPU mode change"
```

---

## Task 7: Packaging and PPA Integration

**Files:**
- Create: `~/utu/debian/control`
- Create: `~/utu/debian/changelog`
- Create: `~/utu/debian/rules`
- Create: `~/utu/debian/copyright`
- Create: `~/utu/debian/utu.desktop`
- Create: `~/asus/packages/utu/upstream.env`
- Create: `~/asus/packages/utu/debian/` (copy from `~/utu/debian/`)
- Modify: `~/asus/packages/asus-suite/debian/control`
- Modify: `~/asus/.github/workflows/build-debs.yml`
- Modify: `~/asus/scripts/upload-ppa.sh` (loop already generic — just add `utu` to the list)

**Interfaces:**
- Produces: `utu_0.1.0~noble1_amd64.deb` installable from the PPA
- Produces: `asus-suite` updated to depend on `utu`

- [ ] **Step 1: Tag v0.1.0 in the utu repo and push**

```bash
cd ~/utu
git tag v0.1.0
git push origin main
git push origin v0.1.0
```

- [ ] **Step 2: Create ~/utu/debian/control**

```
Source: utu
Section: gnome
Priority: optional
Maintainer: Baraka Malila <bmalila87@gmail.com>
Build-Depends: debhelper-compat (= 13), cargo, pkg-config,
 libgtk-4-dev (>= 4.14), libadwaita-1-dev (>= 1.5),
 libdbus-1-dev, libevdev-dev
Standards-Version: 4.6.2
Homepage: https://github.com/Baraka-Malila/utu
Rules-Requires-Root: no

Package: utu
Architecture: amd64
Depends: ${shlibs:Depends}, ${misc:Depends}, asusctl, supergfxctl
Description: ASUS laptop control centre for Ubuntu
 Utu is a GTK4/libadwaita GUI for ASUS laptops on Ubuntu 24.04.
 It provides control over power profiles, GPU switching, keyboard
 backlight, battery charge limit, and more. Hardware features not
 present on the current laptop (AniMatrix, NumberPad, OLED) are
 automatically detected and greyed out.
 .
 Utu is a fork of Ayuz by Guido Philipp, adapted for Ubuntu/GNOME.
```

- [ ] **Step 3: Create ~/utu/debian/changelog**

```
utu (0.1.0~noble1) noble; urgency=medium

  * Phase 3: initial utu release — fork of Ayuz adapted for Ubuntu/GNOME
  * Add Armoury Crate key handler (KEY_PROG1 raises window)
  * Add GDM3 restart prompt after GPU mode switch
  * Replace KDE brightness D-Bus with GNOME SettingsDaemon

 -- Baraka Malila <bmalila87@gmail.com>  Fri, 04 Jul 2026 00:00:00 +0000
```

- [ ] **Step 4: Create ~/utu/debian/rules**

```makefile
#!/usr/bin/make -f
export DH_VERBOSE = 1
export CARGO_HOME = $(CURDIR)/debian/cargo-home
export PATH := $(HOME)/.cargo/bin:$(PATH)

%:
	dh $@

override_dh_auto_build:
	cargo build --release --offline

override_dh_auto_install:
	install -Dm755 target/release/utu \
		$(DESTDIR)/usr/bin/utu
	install -Dm644 debian/utu.desktop \
		$(DESTDIR)/usr/share/applications/io.github.baraka_malila.utu.desktop

override_dh_auto_test:
	# no automated tests
```

Make it executable:

```bash
chmod +x ~/utu/debian/rules
```

- [ ] **Step 5: Create ~/utu/debian/copyright**

```
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: utu (fork of Ayuz)
Upstream-Contact: Baraka Malila <bmalila87@gmail.com>
Source: https://github.com/Baraka-Malila/utu

Files: *
Copyright: 2026 Guido Philipp <guido@example.com>
           2026 Baraka Malila <bmalila87@gmail.com>
License: GPL-3.0+

License: GPL-3.0+
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 .
 On Debian systems, the full text of the GNU General Public License
 version 3 can be found in `/usr/share/common-licenses/GPL-3'.
```

- [ ] **Step 6: Create ~/utu/debian/utu.desktop**

```
[Desktop Entry]
Name=Utu
GenericName=ASUS Laptop Control
Comment=Control power, GPU, keyboard and battery on ASUS laptops
Exec=utu
Icon=io.github.baraka_malila.utu
Terminal=false
Type=Application
Categories=System;Settings;HardwareSettings;
Keywords=asus;rog;tuf;gpu;power;battery;keyboard;
StartupNotify=true
```

- [ ] **Step 7: Create packages/utu/upstream.env in the packaging repo**

```bash
mkdir -p ~/asus/packages/utu
cat > ~/asus/packages/utu/upstream.env << 'EOF'
ORIG_NAME=utu
UPSTREAM_TAG=0.1.0
TARBALL_URL=https://github.com/Baraka-Malila/utu/archive/refs/tags/v0.1.0.tar.gz
CARGO_PKG=1
EOF
```

- [ ] **Step 8: Copy debian/ to packages/utu/debian/**

```bash
cp -r ~/utu/debian ~/asus/packages/utu/debian
```

- [ ] **Step 9: Update asus-suite to depend on utu (Noble only)**

In `~/asus/packages/asus-suite/debian/control`, update the `Depends` line:

```
Depends: asusctl, supergfxctl, asus-backlight-fix, utu [amd64]
```

Also update the package name from `asusctl-suite` to `asus-suite` if not already done:

```
Source: asus-suite
...
Package: asus-suite
```

And update `~/asus/packages/asus-suite/debian/changelog` with a new entry:

```
asus-suite (1.1~noble1) noble; urgency=medium

  * Rename from asusctl-suite to asus-suite
  * Add utu GUI dependency on amd64

 -- Baraka Malila <bmalila87@gmail.com>  Fri, 04 Jul 2026 00:00:00 +0000
```

- [ ] **Step 10: Build utu source package locally**

```bash
cd ~/asus
bash scripts/build-source-package.sh utu noble
```

Expected: creates `~/asus/packages/utu/build/noble/utu_0.1.0~noble1.dsc`

- [ ] **Step 11: Build utu .deb locally**

```bash
cd ~/asus
bash scripts/build-deb-pbuilder.sh utu noble --direct
ls ~/asus/packages/utu/build/noble/*.deb
# Expected: utu_0.1.0~noble1_amd64.deb
```

- [ ] **Step 12: Install and smoke-test**

```bash
sudo dpkg -i ~/asus/packages/utu/build/noble/utu_0.1.0~noble1_amd64.deb
utu &
sleep 3
# Expected: Utu window appears with "Utu — ASUS Laptop Control" title
# Check: GPU switching panel shows current mode
# Check: keyboard backlight panel works
# Check: battery limit panel works
# Press Armoury Crate button: window should raise
kill %1
```

- [ ] **Step 13: Add utu to CI workflow**

In `~/asus/.github/workflows/build-debs.yml`, add `utu` to the Noble-only build matrix. Find the `matrix` section and add `utu` to the Noble packages list. Utu should only appear under the `noble` distro entry — not jammy.

- [ ] **Step 14: Upload utu to PPA**

```bash
cd ~/asus
bash scripts/upload-ppa.sh utu noble
```

Expected: Launchpad accepts the upload and emails `bmalila87@gmail.com` when built.

- [ ] **Step 15: Commit all packaging repo changes**

```bash
cd ~/asus
git add packages/utu/ packages/asus-suite/ .github/workflows/build-debs.yml
git commit -m "Phase 3 Task 7: utu packaging + asus-suite updated"
git push origin HEAD
```

- [ ] **Step 16: Push utu debian/ to utu repo**

```bash
cd ~/utu
git add debian/
git commit -m "packaging: add debian/ for PPA builds"
git push origin main
```

- [ ] **Step 17: End-to-end PPA install test (after Launchpad build completes)**

```bash
sudo add-apt-repository ppa:malila-arch/asusctl-ubuntu
sudo apt update
sudo apt install asus-suite
utu
# Expected: Utu launches, all panels accessible, Armoury key works
```
