# Phase 2c — Launchpad PPA + CI + Noble + Docs

**Date:** 2026-07-03  
**Depends on:** Phase 2b (`phase2b-v0.1-packaging` tag). Four `.deb` packages
build and install cleanly on Jammy.  
**Blocks:** Phase 2b.5 (GUI) — PPA must be live first so the GUI package has
somewhere to land.  
**Test hardware:** ASUS TUF Gaming A15 FA507NV (Jammy). Noble validation via
CI + separate Noble machine (Kali box → Ubuntu 24.04, non-ASUS, packaging
correctness only).

---

## 1. Purpose

Ship `sudo add-apt-repository ppa:malila/asusctl-ubuntu && sudo apt install
asusctl-suite` as a working command for Ubuntu 22.04 (Jammy) and 24.04
(Noble) users. Gate every push behind CI. Provide minimal user-facing docs.

**Explicitly excluded:** DKMS, AppArmor profile, `asusd-user`,
`rog-control-center`, GUI (Phase 2b.5+), Noble functional hardware testing
(no Noble ASUS machine).

---

## 2. Approach: CI-first (B)

```
cargo vendor  →  GitHub Actions CI (Jammy + Noble)  →  Launchpad PPA upload
     ↑                                                          ↑
prerequisite for both                              manual step, after CI green
```

Launchpad account + GPG setup happens in parallel with CI work (interactive,
no coding required). PPA upload is always a manual step triggered by the
maintainer after CI is green.

---

## 3. Task breakdown

| Task | Deliverable | Blocks |
|---|---|---|
| 1 | `cargo vendor` — build script + patches + `--offline` | Tasks 2, 4 |
| 2 | GitHub Actions CI — Jammy + Noble matrix | Task 4 |
| 3 | Noble build script support — distro param + `pbuilderrc-noble` | Task 4 |
| 4 | Launchpad setup — `dput.cf` + guide + first upload | — |
| 5 | User docs — `install.md` + `troubleshoot.md` | — |

---

## 4. Task 1 — `cargo vendor`

### Problem

`cargo build` fetches crates from crates.io during the build. Launchpad
buildds and pbuilder chroots have no outbound network. Build fails silently
or with a network timeout.

### Solution

Pre-bundle all crates into the source tarball using `cargo vendor`. The build
then runs fully offline.

### Changes to `scripts/build-source-package.sh`

After fetching the upstream tarball and applying patches, add a vendor step:

```
1. Fetch upstream .orig.tar.gz (existing)
2. Extract to staging dir (existing)
3. Apply debian/patches (existing)
4. cd into source dir; run: cargo vendor vendor/
5. Add .cargo/config.toml pointing at vendor/
6. Repack as .orig.tar.xz (vendor/ included)
```

The vendored tarball grows from ~2 MB to ~60–80 MB for `asusctl` and ~20 MB
for `supergfxctl`. This is expected.

### New patch: `.cargo/config.toml`

Added via `patches/<pkg>/series` for both Rust packages:

```toml
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
```

### New patch: lower `rust-version` in `asusctl/Cargo.toml`

`asusctl` declares `rust-version = "1.82"`. Jammy ships rustc 1.75. We patch
`Cargo.toml` to `rust-version = "1.75"` so cargo's version check passes on
Jammy. The actual compilation uses rustup 1.82 in CI and `--direct` builds;
this patch only affects the version gate, not what compiles.

### Changes to `debian/rules` (both Rust packages)

Add `--offline` to `cargo build`:

```makefile
# asusctl
override_dh_auto_build:
	cargo build --release --workspace \
	    --offline \
	    --exclude asusd-user \
	    --exclude rog-control-center \
	    --exclude rog_simulators

# supergfxctl
override_dh_auto_build:
	cargo build --release --offline --features "daemon cli"
```

### Files touched

- `scripts/build-source-package.sh`
- `packages/asusctl/debian/rules`
- `packages/supergfxctl/debian/rules`
- `patches/asusctl/series` — two new patches
- `patches/supergfxctl/series` — one new patch

---

## 5. Task 2 — GitHub Actions CI

### Workflow: `.github/workflows/build-debs.yml`

**Triggers:** push to any branch, PR targeting `main`.

**Matrix:**

| Runner | Distro | rustc source |
|---|---|---|
| `ubuntu-22.04` | jammy | rustup 1.82 (distro 1.75 insufficient) |
| `ubuntu-24.04` | noble | rustup 1.82 (consistent with jammy job) |

**Steps per job:**

```
1. actions/checkout
2. apt-get install: debhelper devscripts lintian dpkg-dev
                    libudev-dev libclang-dev libinput-dev pkg-config
3. rustup install 1.82 + set default
4. build-source-package.sh <pkg> <distro>  (x4 packages)
5. build-deb-pbuilder.sh <pkg> --direct     (x4 packages)
6. lintian --fail-on error packages/<pkg>/build/<distro>/*.deb
7. upload-artifact: *.deb files (downloadable from Actions run page)
```

`-d` flag (`--no-check-builddeps`) retained because rustup-installed rustc is
not registered as a dpkg package.

**What CI does NOT do:** install packages or run functional tests. Those
require real ASUS hardware with systemd.

**Files added:**

- `.github/workflows/build-debs.yml`

---

## 6. Task 3 — Noble build script support

### `scripts/build-source-package.sh` — distro parameter

Add optional second argument `DISTRO` (default: `jammy`). The script stamps
the changelog `Distribution:` field and version suffix accordingly:

```bash
PKGNAME="${1:?usage: $0 <pkgname> [distro]}"
DISTRO="${2:-jammy}"
# version becomes e.g. 6.3.8-1~noble1 for noble
```

### `scripts/build-all-debs.sh` — loop both distros

```bash
for DISTRO in jammy noble; do
    for PKG in asusctl supergfxctl asus-backlight-fix asusctl-suite; do
        bash scripts/build-source-package.sh "$PKG" "$DISTRO"
        bash scripts/build-deb-pbuilder.sh "$PKG" "$DISTRO" --direct
    done
done
```

`build-deb-pbuilder.sh` gains a `DISTRO` argument so it locates the correct
`.dsc` in `build/jammy/` or `build/noble/` and places output there.

Output layout:
```
packages/<pkg>/build/jammy/<pkg>_*_amd64.deb
packages/<pkg>/build/noble/<pkg>_*_amd64.deb
```

### `pbuilderrc-noble`

Mirrors `pbuilderrc` with `DISTRIBUTION=noble` and
`BASETGZ=/var/cache/pbuilder/base-noble.tgz`. Used on the Noble test machine
once set up; not needed on the Jammy ASUS machine.

### Files touched / added

- `scripts/build-source-package.sh`
- `scripts/build-all-debs.sh`
- `pbuilderrc-noble` (new)

---

## 7. Task 4 — Launchpad PPA

### Account details

- **Launchpad username:** `malila` (changeable before first upload at zero cost)
- **PPA name:** `asusctl-ubuntu`
- **PPA URL:** `ppa:malila/asusctl-ubuntu`
- **Install command:** `sudo add-apt-repository ppa:malila/asusctl-ubuntu`

### One-time setup (interactive, done by maintainer)

1. Create account at `launchpad.net` — username: `malila`
2. Create PPA: `launchpad.net/~malila/+activate-ppa` — name: `asusctl-ubuntu`
3. `gpg --gen-key` (RSA 4096, name: Baraka Malila, email: bmalila87@gmail.com)
4. `gpg --keyserver keyserver.ubuntu.com --send-keys <KEY_ID>`
5. Register key fingerprint in Launchpad → Settings → OpenPGP keys

Full walkthrough in `docs/launchpad-setup.md`.

### Per-release upload workflow

```bash
# 1. CI is green on main
# 2. Build signed source packages for both distros
bash scripts/build-all-debs.sh  # produces .changes + .dsc for jammy + noble

# 3. Upload
dput ppa:malila/asusctl-ubuntu packages/asusctl/build/jammy/asusctl_*.changes
dput ppa:malila/asusctl-ubuntu packages/asusctl/build/noble/asusctl_*.changes
# repeat for supergfxctl, asus-backlight-fix, asusctl-suite

# 4. Wait for Launchpad build email (~10–20 min)
```

Source packages must be GPG-signed (`debsign`) before `dput`. The
`build-source-package.sh` script calls `debsign` at the end if a GPG key is
available; CI skips signing (`--no-sign`).

### `dput.cf` (repo root, committed)

```ini
[malila-asusctl]
fqdn = ppa.launchpad.net
method = ftp
incoming = ~malila/ubuntu/asusctl-ubuntu
login = anonymous
allow_unsigned_uploads = 0
```

### Files added

- `dput.cf`
- `docs/launchpad-setup.md`

---

## 8. Task 5 — User docs

### `docs/install.md`

Target: terminal-comfortable ASUS TUF/ROG users on Ubuntu 22.04 or 24.04.
Provisional — will be updated as the project matures.

```markdown
## Install

sudo add-apt-repository ppa:malila/asusctl-ubuntu
sudo apt update
sudo apt install asusctl-suite
reboot

## Quick reference

asusctl profile set Quiet|Balanced|Performance
asusctl battery limit 80
asusctl leds set off|low|med|high
supergfxctl -g              # current GPU mode
supergfxctl -m Hybrid       # switch to hybrid (reboot required)
```

### `docs/troubleshoot.md`

Four issues, direct fixes:

1. **Services not starting** — `systemctl status asusd`, `journalctl -u asusd`
2. **Backlight fix not activating** — check postinst hardware detection output;
   manual `update-initramfs -u` if needed
3. **GPU mode not switching** — nvidia-prime coexistence note; check
   `supergfxctl -g` output
4. **Battery threshold ignored** — check for conflict with
   `battery-charge-threshold.service`; asusctl should have disabled it on
   install

### Files added

- `docs/install.md`
- `docs/troubleshoot.md`

---

## 9. Version scheme (Noble additions)

| Package | Jammy | Noble |
|---|---|---|
| `asusctl` | `6.3.8-1~jammy1` | `6.3.8-1~noble1` |
| `supergfxctl` | `5.2.7-1~jammy1` | `5.2.7-1~noble1` |
| `asus-backlight-fix` | `1.0~jammy1` | `1.0~noble1` |
| `asusctl-suite` | `1.0~jammy1` | `1.0~noble1` |

---

## 10. Release cadence

Event-driven, not scheduled. New release when:
- Upstream (asusctl / supergfxctl) tags a new version
- A packaging bug fix is merged to `main`
- A new feature or hardware fix is ready
- A contributor PR is accepted

Steps: bump changelog → CI green → `dput` for each package × each distro.
