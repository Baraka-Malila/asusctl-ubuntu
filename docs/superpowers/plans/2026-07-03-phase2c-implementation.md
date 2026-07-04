# Phase 2c Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `sudo add-apt-repository ppa:malila/asusctl-ubuntu && sudo apt install asusctl-suite` as a working command for Ubuntu 22.04 (Jammy) and 24.04 (Noble), with CI gating every push.

**Architecture:** cargo vendor embeds all Rust crates in the source tarball so Launchpad buildds can build offline. GitHub Actions CI validates both distros on every push. Upload to PPA is always a manual step after CI is green.

**Tech Stack:** bash, dpkg-buildpackage, pbuilder, cargo vendor, GitHub Actions, Launchpad PPA, dput, debsign, GPG.

## Global Constraints

- Ubuntu targets: Jammy (22.04) and Noble (24.04) — both required.
- Launchpad username: `malila`. PPA name: `asusctl-ubuntu`. Full URL: `ppa:malila/asusctl-ubuntu`.
- rustc toolchain: 1.82 via rustup in CI and `--direct` builds. `-d` flag always used with `dpkg-buildpackage -b` to skip dpkg build-dep check.
- Version suffix scheme: `~jammy1` / `~noble1` — stamped at source-package-build time.
- `.orig.tar.xz` cached at `packages/<pkg>/build/` (shared across distros). Distro-specific output in `packages/<pkg>/build/<distro>/`.
- `packages/*/build/` is gitignored — never commit build artifacts.
- File length hard limit: 300 lines.

---

## File Map

| File | Action | Task |
|---|---|---|
| `scripts/build-source-package.sh` | Modify: add `CARGO_PKG` vendor step | 1 |
| `packages/asusctl/upstream.env` | Modify: add `CARGO_PKG=1` | 1 |
| `packages/supergfxctl/upstream.env` | Modify: add `CARGO_PKG=1` | 1 |
| `patches/asusctl/0004-rust-version-floor.patch` | Create | 1 |
| `patches/asusctl/series` | Modify: append new patch | 1 |
| `packages/asusctl/debian/rules` | Modify: add `--offline` | 1 |
| `packages/supergfxctl/debian/rules` | Modify: add `--offline` | 1 |
| `scripts/build-source-package.sh` | Modify: add DISTRO param + distro output dirs | 2 |
| `scripts/build-deb-pbuilder.sh` | Modify: add DISTRO param | 2 |
| `scripts/build-all-debs.sh` | Modify: loop over both distros | 2 |
| `pbuilderrc-noble` | Create | 2 |
| `.github/workflows/build-debs.yml` | Create | 3 |
| `dput.cf` | Create | 4 |
| `scripts/upload-ppa.sh` | Create | 4 |
| `docs/launchpad-setup.md` | Create | 4 |
| `docs/install.md` | Create | 5 |
| `docs/troubleshoot.md` | Create | 5 |

---

## Task 1: cargo vendor

**Files:**
- Modify: `scripts/build-source-package.sh`
- Modify: `packages/asusctl/upstream.env`
- Modify: `packages/supergfxctl/upstream.env`
- Create: `patches/asusctl/0004-rust-version-floor.patch`
- Modify: `patches/asusctl/series`
- Modify: `packages/asusctl/debian/rules`
- Modify: `packages/supergfxctl/debian/rules`

**What this task does:** Makes both Rust packages build fully offline by bundling all crates into the `.orig.tar.xz`. Launchpad buildds have no internet; this is a hard requirement for PPA upload.

**Interfaces:**
- Produces: `packages/asusctl/build/asusctl_6.3.8.orig.tar.xz` containing `vendor/` and `.cargo/config.toml` (~70 MB). Task 2 relies on this file being present.

- [ ] **Step 1: Mark Rust packages in upstream.env**

```bash
echo "CARGO_PKG=1" >> /home/cyberpunk/asus/packages/asusctl/upstream.env
echo "CARGO_PKG=1" >> /home/cyberpunk/asus/packages/supergfxctl/upstream.env
```

Verify:
```bash
grep CARGO_PKG /home/cyberpunk/asus/packages/asusctl/upstream.env
grep CARGO_PKG /home/cyberpunk/asus/packages/supergfxctl/upstream.env
```
Expected: `CARGO_PKG=1` in both files.

- [ ] **Step 2: Add vendor step to build-source-package.sh**

Replace `scripts/build-source-package.sh` with this complete file (vendor step added in the tarball-fetch block; NO_UPSTREAM path unchanged):

```bash
#!/usr/bin/env bash
# Generate a Debian source package for one of our packages.
#   Usage: scripts/build-source-package.sh <pkgname>
#
# upstream.env exports:
#   UPSTREAM_TAG, ORIG_NAME, TARBALL_URL
#   CARGO_PKG=1  (optional) — run cargo vendor + add .cargo/config.toml
#   NO_UPSTREAM=1 — skip tarball fetch; use debian/ + files/ as-is
set -euo pipefail

PKGNAME="${1:?usage: $0 <pkgname>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$REPO_ROOT/packages/$PKGNAME"
BUILD_DIR="$PKG_DIR/build"
PATCHES_SRC="$REPO_ROOT/patches/$PKGNAME"

[ -f "$PKG_DIR/upstream.env" ] || { echo "ERROR: $PKG_DIR/upstream.env missing" >&2; exit 1; }
# shellcheck disable=SC1090
source "$PKG_DIR/upstream.env"

mkdir -p "$BUILD_DIR"

if [ "${NO_UPSTREAM:-0}" = "1" ]; then
    STAGE="$BUILD_DIR/stage"
    rm -rf "$STAGE" && mkdir -p "$STAGE"
    cp -a "$PKG_DIR/debian" "$STAGE/"
    [ -d "$PKG_DIR/files" ] && cp -a "$PKG_DIR/files" "$STAGE/"
    (cd "$BUILD_DIR" && dpkg-source -b stage)
    rm -rf "$STAGE"
    echo "==> Source package built for $PKGNAME (NO_UPSTREAM)"
    exit 0
fi

ORIG_TARBALL="$BUILD_DIR/${ORIG_NAME}_${UPSTREAM_TAG}.orig.tar.xz"
if [ ! -f "$ORIG_TARBALL" ]; then
    echo "==> Fetching $TARBALL_URL"
    TMPGZ=$(mktemp --suffix=.tar.gz)
    curl -fsSL "$TARBALL_URL" -o "$TMPGZ"

    if [ "${CARGO_PKG:-0}" = "1" ]; then
        echo "==> Running cargo vendor (takes several minutes on first run)"
        VSTAGE=$(mktemp -d)
        tar -xf "$TMPGZ" -C "$VSTAGE"
        SRCDIR=$(ls "$VSTAGE")
        (cd "$VSTAGE/$SRCDIR" && cargo vendor vendor/)
        mkdir -p "$VSTAGE/$SRCDIR/.cargo"
        cat > "$VSTAGE/$SRCDIR/.cargo/config.toml" <<'CARGO_CONF'
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
CARGO_CONF
        tar -cJf "$ORIG_TARBALL" -C "$VSTAGE" "$SRCDIR"
        rm -rf "$VSTAGE"
    else
        gunzip -c "$TMPGZ" | xz -c > "$ORIG_TARBALL"
    fi
    rm -f "$TMPGZ"
fi

STAGE="$BUILD_DIR/stage"
rm -rf "$STAGE" && mkdir -p "$STAGE"
(cd "$STAGE" && tar --strip-components=1 -xf "$ORIG_TARBALL")
cp -a "$PKG_DIR/debian" "$STAGE/"

if [ -d "$PATCHES_SRC" ]; then
    mkdir -p "$STAGE/debian/patches"
    cp "$PATCHES_SRC"/*.patch "$STAGE/debian/patches/" 2>/dev/null || true
    cp "$PATCHES_SRC/series"  "$STAGE/debian/patches/series"
fi

(cd "$BUILD_DIR" && dpkg-source -b stage)
rm -rf "$STAGE"
echo "==> Source package built for $PKGNAME"
```

- [ ] **Step 3: Create the rust-version-floor patch for asusctl**

Inspect the upstream `Cargo.toml` to find the exact `rust-version` line:

```bash
mkdir -p /tmp/asusctl-inspect
curl -fsSL "https://github.com/OpenGamingCollective/asusctl/archive/refs/tags/6.3.8.tar.gz" | \
    tar -xz -C /tmp/asusctl-inspect --strip-components=1
grep -n "rust-version" /tmp/asusctl-inspect/Cargo.toml
```

Expected output: a line like `rust-version = "1.82"` with its line number.

Now create the patch:

```bash
cd /tmp/asusctl-inspect
cp Cargo.toml Cargo.toml.orig
sed -i 's/rust-version = "1\.82"/rust-version = "1.75"/' Cargo.toml
diff -u Cargo.toml.orig Cargo.toml \
    --label a/Cargo.toml --label b/Cargo.toml \
    > /home/cyberpunk/asus/patches/asusctl/0004-rust-version-floor.patch
cd /home/cyberpunk/asus
rm -rf /tmp/asusctl-inspect
```

Prepend a subject header to the patch file so it matches quilt conventions:

```bash
PATCH=/home/cyberpunk/asus/patches/asusctl/0004-rust-version-floor.patch
TMP=$(mktemp)
cat > "$TMP" <<'HEADER'
Subject: Lower rust-version floor from 1.82 to 1.75 for Jammy compatibility

Jammy's rustc is 1.75. This patch tells cargo's version gate to accept it.
The actual build uses rustup 1.82 in both CI and --direct builds; this only
relaxes the version floor check.

---
HEADER
cat "$TMP" "$PATCH" > "${PATCH}.new"
mv "${PATCH}.new" "$PATCH"
rm "$TMP"
```

Verify the patch file looks correct:

```bash
head -20 /home/cyberpunk/asus/patches/asusctl/0004-rust-version-floor.patch
```

Expected: subject header followed by `--- a/Cargo.toml` / `+++ b/Cargo.toml` diff.

- [ ] **Step 4: Add the patch to patches/asusctl/series**

```bash
echo "0004-rust-version-floor.patch" >> /home/cyberpunk/asus/patches/asusctl/series
```

Verify:

```bash
tail -2 /home/cyberpunk/asus/patches/asusctl/series
```

Expected: last two lines are `0003-gpu-mode-per-power.patch` and `0004-rust-version-floor.patch`.

- [ ] **Step 5: Add --offline to asusctl debian/rules**

Edit `packages/asusctl/debian/rules`. Change the `override_dh_auto_build` target to:

```makefile
override_dh_auto_build:
	cargo build --release --workspace \
	    --offline \
	    --exclude asusd-user \
	    --exclude rog-control-center \
	    --exclude rog_simulators
```

(One tab before `cargo`, two tabs before continuation lines — makefile syntax.)

- [ ] **Step 6: Add --offline to supergfxctl debian/rules**

Edit `packages/supergfxctl/debian/rules`. Change the `override_dh_auto_build` target to:

```makefile
override_dh_auto_build:
	cargo build --release --offline --features "daemon cli"
```

- [ ] **Step 7: Run cargo vendor for asusctl and verify**

The Phase 2b build left a non-vendored `.orig.tar.xz` in place. Delete it so
the new vendor step runs:

```bash
cd /home/cyberpunk/asus
rm -f packages/asusctl/build/asusctl_6.3.8.orig.tar.xz
bash scripts/build-source-package.sh asusctl
```

This will take several minutes on first run (downloading all crates). Expected output ends with:
```
==> Source package built for asusctl
```

Verify `vendor/` is in the tarball:

```bash
tar tf packages/asusctl/build/asusctl_6.3.8.orig.tar.xz | grep '/vendor/' | head -5
```

Expected: lines like `asusctl-6.3.8/vendor/ahash/Cargo.toml` etc.

Verify `.cargo/config.toml` is in the tarball:

```bash
tar tf packages/asusctl/build/asusctl_6.3.8.orig.tar.xz | grep config.toml
```

Expected: `asusctl-6.3.8/.cargo/config.toml`

- [ ] **Step 8: Build asusctl binary and verify offline**

```bash
bash scripts/build-deb-pbuilder.sh asusctl --direct 2>&1 | tee /tmp/asusctl-build.log
grep -i "network\|download\|fetching" /tmp/asusctl-build.log || echo "No network activity (good)"
ls packages/asusctl/build/asusctl_6.3.8-1~jammy1_amd64.deb
```

Expected: `.deb` present, no network fetching lines in the log.

- [ ] **Step 9: Run cargo vendor for supergfxctl and verify**

```bash
rm -f packages/supergfxctl/build/supergfxctl_5.2.7.orig.tar.xz
bash scripts/build-source-package.sh supergfxctl
tar tf packages/supergfxctl/build/supergfxctl_5.2.7.orig.tar.xz | grep '/vendor/' | head -3
bash scripts/build-deb-pbuilder.sh supergfxctl --direct
ls packages/supergfxctl/build/supergfxctl_5.2.7-1~jammy1_amd64.deb
```

Expected: both vendor check and binary build succeed.

- [ ] **Step 10: Commit**

```bash
cd /home/cyberpunk/asus
git add scripts/build-source-package.sh \
        packages/asusctl/upstream.env \
        packages/supergfxctl/upstream.env \
        patches/asusctl/0004-rust-version-floor.patch \
        patches/asusctl/series \
        packages/asusctl/debian/rules \
        packages/supergfxctl/debian/rules
git commit -m "$(cat <<'EOF'
Phase 2c Task 1: cargo vendor for offline Rust builds

Both Rust packages now bundle all crates in .orig.tar.xz via cargo vendor.
build-source-package.sh runs cargo vendor when CARGO_PKG=1 is set in
upstream.env. debian/rules adds --offline to cargo build. Patch lowers
asusctl rust-version floor to 1.75 so Jammy's rustc passes the version gate.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Noble build script support

**Files:**
- Modify: `scripts/build-source-package.sh` (add DISTRO param)
- Modify: `scripts/build-deb-pbuilder.sh` (add DISTRO param)
- Modify: `scripts/build-all-debs.sh` (loop both distros)
- Create: `pbuilderrc-noble`

**Interfaces:**
- Consumes: `packages/<pkg>/build/<pkg>_*.orig.tar.xz` from Task 1.
- Produces: `packages/<pkg>/build/jammy/` and `packages/<pkg>/build/noble/` directories with `.dsc` + `.deb` files. Task 3 (CI) references these paths.

- [ ] **Step 1: Replace build-source-package.sh with distro-aware version**

Full replacement of `scripts/build-source-package.sh`:

```bash
#!/usr/bin/env bash
# Generate a Debian source package for one of our packages.
#   Usage: scripts/build-source-package.sh <pkgname> [distro]
#
# upstream.env exports:
#   UPSTREAM_TAG, ORIG_NAME, TARBALL_URL
#   CARGO_PKG=1  (optional) — run cargo vendor + add .cargo/config.toml
#   NO_UPSTREAM=1 — skip tarball fetch; use debian/ + files/ as-is
set -euo pipefail

PKGNAME="${1:?usage: $0 <pkgname> [distro]}"
DISTRO="${2:-jammy}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$REPO_ROOT/packages/$PKGNAME"
BUILD_DIR="$PKG_DIR/build"
DIST_DIR="$PKG_DIR/build/$DISTRO"
PATCHES_SRC="$REPO_ROOT/patches/$PKGNAME"

[ -f "$PKG_DIR/upstream.env" ] || { echo "ERROR: $PKG_DIR/upstream.env missing" >&2; exit 1; }
# shellcheck disable=SC1090
source "$PKG_DIR/upstream.env"

mkdir -p "$BUILD_DIR" "$DIST_DIR"

if [ "${NO_UPSTREAM:-0}" = "1" ]; then
    STAGE="$DIST_DIR/stage"
    rm -rf "$STAGE" && mkdir -p "$STAGE"
    cp -a "$PKG_DIR/debian" "$STAGE/"
    [ -d "$PKG_DIR/files" ] && cp -a "$PKG_DIR/files" "$STAGE/"
    [ "$DISTRO" != "jammy" ] && \
        sed -i "s/~jammy1/~${DISTRO}1/g; s/) jammy;/) ${DISTRO};/" \
            "$STAGE/debian/changelog"
    (cd "$DIST_DIR" && dpkg-source -b stage)
    rm -rf "$STAGE"
    echo "==> Source package built for $PKGNAME ($DISTRO) [NO_UPSTREAM]"
    exit 0
fi

ORIG_TARBALL="$BUILD_DIR/${ORIG_NAME}_${UPSTREAM_TAG}.orig.tar.xz"
if [ ! -f "$ORIG_TARBALL" ]; then
    echo "==> Fetching $TARBALL_URL"
    TMPGZ=$(mktemp --suffix=.tar.gz)
    curl -fsSL "$TARBALL_URL" -o "$TMPGZ"

    if [ "${CARGO_PKG:-0}" = "1" ]; then
        echo "==> Running cargo vendor (takes several minutes on first run)"
        VSTAGE=$(mktemp -d)
        tar -xf "$TMPGZ" -C "$VSTAGE"
        SRCDIR=$(ls "$VSTAGE")
        (cd "$VSTAGE/$SRCDIR" && cargo vendor vendor/)
        mkdir -p "$VSTAGE/$SRCDIR/.cargo"
        cat > "$VSTAGE/$SRCDIR/.cargo/config.toml" <<'CARGO_CONF'
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
CARGO_CONF
        tar -cJf "$ORIG_TARBALL" -C "$VSTAGE" "$SRCDIR"
        rm -rf "$VSTAGE"
    else
        gunzip -c "$TMPGZ" | xz -c > "$ORIG_TARBALL"
    fi
    rm -f "$TMPGZ"
fi

# dpkg-source looks for .orig.tar.xz in parent of the stage dir (= DIST_DIR)
ln -sf "../$(basename "$ORIG_TARBALL")" \
    "$DIST_DIR/$(basename "$ORIG_TARBALL")" 2>/dev/null || true

STAGE="$DIST_DIR/stage"
rm -rf "$STAGE" && mkdir -p "$STAGE"
(cd "$STAGE" && tar --strip-components=1 -xf "$ORIG_TARBALL")
cp -a "$PKG_DIR/debian" "$STAGE/"

if [ -d "$PATCHES_SRC" ]; then
    mkdir -p "$STAGE/debian/patches"
    cp "$PATCHES_SRC"/*.patch "$STAGE/debian/patches/" 2>/dev/null || true
    cp "$PATCHES_SRC/series"  "$STAGE/debian/patches/series"
fi

[ "$DISTRO" != "jammy" ] && \
    sed -i "s/~jammy1/~${DISTRO}1/g; s/) jammy;/) ${DISTRO};/" \
        "$STAGE/debian/changelog"

(cd "$DIST_DIR" && dpkg-source -b stage)
rm -rf "$STAGE"
echo "==> Source package built for $PKGNAME ($DISTRO)"
```

- [ ] **Step 2: Replace build-deb-pbuilder.sh with distro-aware version**

Full replacement of `scripts/build-deb-pbuilder.sh`:

```bash
#!/usr/bin/env bash
# Build a binary .deb from a source package.
#   Usage: scripts/build-deb-pbuilder.sh <pkgname> [distro] [--direct]
#
# --direct: bypass pbuilder and build on the host via dpkg-buildpackage.
#   Required for Rust packages (cargo vendor handles offline crate deps).
set -euo pipefail

PKGNAME="${1:?usage: $0 <pkgname> [distro] [--direct]}"
DISTRO="jammy"
DIRECT=0
for arg in "${@:2}"; do
    case "$arg" in
        --direct) DIRECT=1 ;;
        jammy|noble) DISTRO="$arg" ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/packages/$PKGNAME/build/$DISTRO"
DSC=$(ls "$BUILD_DIR"/*.dsc 2>/dev/null | head -1)
[ -n "$DSC" ] || {
    echo "ERROR: no .dsc under $BUILD_DIR — run build-source-package.sh first" >&2
    exit 1
}

if [ "$DIRECT" = "1" ]; then
    echo "==> Direct host build: $DSC"
    STAGE="$BUILD_DIR/stage-direct"
    rm -rf "$STAGE" && mkdir -p "$STAGE"
    (cd "$STAGE" && dpkg-source -x "../$(basename "$DSC")" src)
    # -d: skip build-dep check (rustc/cargo via rustup, not dpkg packages)
    (cd "$STAGE/src" && PATH="$HOME/.cargo/bin:$PATH" dpkg-buildpackage -b --no-sign -d)
    mv "$STAGE"/*.deb "$BUILD_DIR/" 2>/dev/null || true
    mv "$STAGE"/*.buildinfo "$BUILD_DIR/" 2>/dev/null || true
    rm -rf "$STAGE"
else
    PBUILDERRC="$REPO_ROOT/pbuilderrc"
    [ "$DISTRO" = "noble" ] && PBUILDERRC="$REPO_ROOT/pbuilderrc-noble"
    echo "==> pbuilder build: $DSC"
    sudo pbuilder build --configfile "$PBUILDERRC" \
        --buildresult "$BUILD_DIR" "$DSC"
fi

echo "==> Artifacts in $BUILD_DIR:"
ls -lh "$BUILD_DIR"/*.deb 2>&1
```

- [ ] **Step 3: Replace build-all-debs.sh to loop both distros**

Full replacement of `scripts/build-all-debs.sh`:

```bash
#!/usr/bin/env bash
# Build source + binary for all four packages, for both jammy and noble.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

for DISTRO in jammy noble; do
    for pkg in asus-backlight-fix asusctl supergfxctl asusctl-suite; do
        echo "===== $pkg ($DISTRO) ====="
        ./scripts/build-source-package.sh "$pkg" "$DISTRO"
        ./scripts/build-deb-pbuilder.sh   "$pkg" "$DISTRO" --direct
    done
done

echo "==> All packages built. Artifacts:"
find packages/*/build -maxdepth 2 -name '*.deb' | sort
```

- [ ] **Step 4: Create pbuilderrc-noble**

Create `/home/cyberpunk/asus/pbuilderrc-noble`:

```bash
# Noble pbuilder config for asusctl-ubuntu Phase 2c
DISTRIBUTION=noble
COMPONENTS="main universe restricted multiverse"
MIRRORSITE=http://archive.ubuntu.com/ubuntu
OTHERMIRROR="deb http://archive.ubuntu.com/ubuntu noble-updates main universe restricted multiverse"
BASETGZ=/var/cache/pbuilder/base-noble.tgz
BUILDPLACE=/var/cache/pbuilder/build
BUILDRESULT=/var/cache/pbuilder/result
APTCACHE=/var/cache/pbuilder/aptcache
DEBBUILDOPTS="-b"
EXTRAPACKAGES="ca-certificates gnupg"
```

- [ ] **Step 5: Test noble build for all four packages**

Delete the cached `.orig.tar.xz` files to force a fresh fetch (vendor step will re-run):

```bash
cd /home/cyberpunk/asus
rm -f packages/asusctl/build/asusctl_6.3.8.orig.tar.xz
rm -f packages/supergfxctl/build/supergfxctl_5.2.7.orig.tar.xz
```

Build all packages for noble (takes ~10 min for the two Rust packages):

```bash
for pkg in asus-backlight-fix asusctl supergfxctl asusctl-suite; do
    bash scripts/build-source-package.sh "$pkg" noble
    bash scripts/build-deb-pbuilder.sh "$pkg" noble --direct
done
```

Verify output:

```bash
find packages/*/build/noble -maxdepth 1 -name '*.deb' | sort
```

Expected (four lines):
```
packages/asus-backlight-fix/build/noble/asus-backlight-fix_1.0~noble1_all.deb
packages/asusctl/build/noble/asusctl_6.3.8-1~noble1_amd64.deb
packages/asusctl-suite/build/noble/asusctl-suite_1.0~noble1_all.deb
packages/supergfxctl/build/noble/supergfxctl_5.2.7-1~noble1_amd64.deb
```

Verify noble version strings in the .dsc files:

```bash
grep ^Version packages/asusctl/build/noble/asusctl_6.3.8-1~noble1.dsc
```

Expected: `Version: 6.3.8-1~noble1`

- [ ] **Step 6: Commit**

```bash
cd /home/cyberpunk/asus
git add scripts/build-source-package.sh \
        scripts/build-deb-pbuilder.sh \
        scripts/build-all-debs.sh \
        pbuilderrc-noble
git commit -m "$(cat <<'EOF'
Phase 2c Task 2: Noble build script support

build-source-package.sh and build-deb-pbuilder.sh gain a DISTRO parameter
(default: jammy). Output goes to packages/<pkg>/build/<distro>/. Changelog
is stamped ~noble1 for noble builds. build-all-debs.sh loops both distros.
pbuilderrc-noble added for Noble test machine.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: GitHub Actions CI

**Files:**
- Create: `.github/workflows/build-debs.yml`

**Interfaces:**
- Consumes: `scripts/build-source-package.sh <pkg> <distro>` and `scripts/build-deb-pbuilder.sh <pkg> <distro> --direct` from Tasks 1–2.
- Produces: CI check on every push + downloadable `.deb` artifacts per run.

- [ ] **Step 1: Create .github/workflows/build-debs.yml**

```bash
mkdir -p /home/cyberpunk/asus/.github/workflows
```

Create `/home/cyberpunk/asus/.github/workflows/build-debs.yml`:

```yaml
name: Build Debian packages

on:
  push:
  pull_request:
    branches: [main]

jobs:
  build:
    strategy:
      matrix:
        include:
          - runner: ubuntu-22.04
            distro: jammy
          - runner: ubuntu-24.04
            distro: noble
    runs-on: ${{ matrix.runner }}
    name: build (${{ matrix.distro }})

    steps:
      - uses: actions/checkout@v4

      - name: Install build dependencies
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y --no-install-recommends \
            debhelper devscripts lintian dpkg-dev quilt \
            libudev-dev libclang-dev libinput-dev pkg-config \
            curl ca-certificates

      - name: Install rustc 1.82 via rustup
        run: |
          curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
            sh -s -- -y --default-toolchain 1.82 --profile minimal
          echo "$HOME/.cargo/bin" >> "$GITHUB_PATH"

      - name: Build source + binary packages
        run: |
          for pkg in asus-backlight-fix asusctl supergfxctl asusctl-suite; do
            bash scripts/build-source-package.sh "$pkg" "${{ matrix.distro }}"
            bash scripts/build-deb-pbuilder.sh "$pkg" "${{ matrix.distro }}" --direct
          done

      - name: Lintian
        run: |
          find packages/*/build/${{ matrix.distro }} -maxdepth 1 -name '*.deb' \
            -exec lintian --fail-on error {} \;

      - name: Upload .deb artifacts
        uses: actions/upload-artifact@v4
        with:
          name: debs-${{ matrix.distro }}
          path: packages/*/build/${{ matrix.distro }}/*.deb
          if-no-files-found: error
```

- [ ] **Step 2: Commit and push to trigger CI**

```bash
cd /home/cyberpunk/asus
git add .github/workflows/build-debs.yml
git commit -m "$(cat <<'EOF'
Phase 2c Task 3: GitHub Actions CI (Jammy + Noble matrix)

Builds all four packages on ubuntu-22.04 (jammy) and ubuntu-24.04 (noble)
on every push. Installs rustc 1.82 via rustup. Runs lintian --fail-on error.
Uploads .deb artifacts per run.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

- [ ] **Step 3: Verify CI passes**

Go to `https://github.com/Baraka-Malila/asusctl-ubuntu/actions` and confirm:
- `build (jammy)` job: green
- `build (noble)` job: green
- Both jobs upload `.deb` artifact files

If a job fails, check the failing step's log. Common causes:
- Missing apt package: add it to the `apt-get install` line
- Lintian error: fix the relevant `debian/` file and push again

---

## Task 4: Launchpad PPA setup

**Files:**
- Create: `dput.cf`
- Create: `scripts/upload-ppa.sh`
- Create: `docs/launchpad-setup.md`

**Note:** The interactive Launchpad + GPG setup steps are done by the maintainer manually outside the repo. This task commits the tooling and guide.

- [ ] **Step 1: Create dput.cf**

Create `/home/cyberpunk/asus/dput.cf`:

```ini
[malila-asusctl]
fqdn = ppa.launchpad.net
method = ftp
incoming = ~malila/ubuntu/asusctl-ubuntu
login = anonymous
allow_unsigned_uploads = 0
```

- [ ] **Step 2: Create scripts/upload-ppa.sh**

Create `/home/cyberpunk/asus/scripts/upload-ppa.sh`:

```bash
#!/usr/bin/env bash
# Sign and upload a source package to ppa:malila/asusctl-ubuntu.
#   Usage: scripts/upload-ppa.sh <pkgname> [distro]
# Requires: devscripts (debsign), dput, GPG key for bmalila87@gmail.com
set -euo pipefail

PKGNAME="${1:?usage: $0 <pkgname> [distro]}"
DISTRO="${2:-jammy}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$REPO_ROOT/packages/$PKGNAME/build/$DISTRO"

DSC=$(ls "$DIST_DIR"/*.dsc 2>/dev/null | head -1)
[ -n "$DSC" ] || {
    echo "ERROR: no .dsc in $DIST_DIR — run build-source-package.sh first" >&2
    exit 1
}

gpg --list-secret-keys bmalila87@gmail.com >/dev/null 2>&1 || {
    echo "ERROR: GPG key for bmalila87@gmail.com not found" >&2
    echo "       Follow docs/launchpad-setup.md to set up your GPG key." >&2
    exit 1
}

STAGE="$DIST_DIR/stage-upload"
rm -rf "$STAGE" && mkdir -p "$STAGE"

echo "==> Building signed source package for $PKGNAME ($DISTRO)"
(cd "$STAGE" && dpkg-source -x "$(realpath "$DSC")" src)
# -d: skip build-dep check; -S: source-only build
(cd "$STAGE/src" && dpkg-buildpackage -S --no-sign -d)
debsign "$STAGE"/*_source.changes

echo "==> Uploading to ppa:malila/asusctl-ubuntu"
dput --config "$REPO_ROOT/dput.cf" malila-asusctl \
    "$STAGE"/*_source.changes

rm -rf "$STAGE"
echo "==> Done. Launchpad will email bmalila87@gmail.com when the build completes."
```

Make executable:

```bash
chmod +x /home/cyberpunk/asus/scripts/upload-ppa.sh
```

- [ ] **Step 3: Create docs/launchpad-setup.md**

Create `/home/cyberpunk/asus/docs/launchpad-setup.md`:

```markdown
# Launchpad PPA Setup

One-time setup for `ppa:malila/asusctl-ubuntu`. Do this once before the first
upload. All steps are on your local machine.

## 1. Create a Launchpad account

Go to https://launchpad.net and sign up. When asked for a username, enter:
`malila`

(Username is changeable before the first upload with zero cost to users.)

## 2. Create the PPA

After logging in, go to:
https://launchpad.net/~malila/+activate-ppa

Fill in:
- Name: `asusctl-ubuntu`
- Display name: ASUS Linux Ubuntu
- Description: Ubuntu packaging for asusctl + supergfxctl

## 3. Generate a GPG key

```bash
gpg --full-gen-key
```

At the prompts:
- Key type: RSA and RSA (option 1)
- Key size: 4096
- Expiry: 0 (does not expire)
- Real name: Baraka Malila
- Email: bmalila87@gmail.com
- Comment: (leave blank, press Enter)
- Passphrase: choose a strong one

## 4. Upload your key to Ubuntu's keyserver

```bash
# Find your key ID (the long hex string after rsa4096/)
gpg --list-secret-keys --keyid-format LONG bmalila87@gmail.com
# Example output:
# sec   rsa4096/ABCD1234EFGH5678 2026-07-03 [SC]

# Upload (replace with your actual key ID)
gpg --keyserver keyserver.ubuntu.com --send-keys ABCD1234EFGH5678
```

## 5. Register the key in Launchpad

Get your key fingerprint:
```bash
gpg --fingerprint bmalila87@gmail.com
```

Copy the fingerprint (40 hex chars with spaces, like
`XXXX XXXX XXXX XXXX XXXX  XXXX XXXX XXXX XXXX XXXX`).

Go to: https://launchpad.net/~malila/+editpgpkeys
Paste the fingerprint and click "Import Key".

Launchpad emails `bmalila87@gmail.com` with an encrypted confirmation message.
Decrypt it to get the confirmation link:
```bash
# Paste the encrypted block (everything between ---BEGIN and ---END), then Ctrl+D
gpg --decrypt
```

Click the link in the decrypted output to confirm.

## 6. Install upload tools

```bash
sudo apt-get install -y devscripts dput
```

## 7. Verify setup

```bash
gpg --list-secret-keys bmalila87@gmail.com   # should list your key
dput --version                                # should print a version number
```

## Uploading packages (per release)

CI must be green on main before uploading.

```bash
cd /home/cyberpunk/asus

# Upload all packages for jammy
for pkg in asus-backlight-fix asusctl supergfxctl asusctl-suite; do
    bash scripts/upload-ppa.sh "$pkg" jammy
done

# Upload all packages for noble
for pkg in asus-backlight-fix asusctl supergfxctl asusctl-suite; do
    bash scripts/upload-ppa.sh "$pkg" noble
done
```

Launchpad emails `bmalila87@gmail.com` when each build completes (~10–20 min).
If a build fails, the email contains the build log URL.

## Releasing a new upstream version

1. Update `UPSTREAM_TAG` and `TARBALL_URL` in `packages/<pkg>/upstream.env`
2. Delete the cached `.orig.tar.xz`: `rm packages/<pkg>/build/<pkg>_*.orig.tar.xz`
3. Add a new changelog entry: `dch -v <new-version>~jammy1 "Update to <version>"`
4. Ensure CI is green
5. Run `upload-ppa.sh` for each package × each distro

Launchpad versions must be strictly increasing: `6.3.9-1~jammy1` > `6.3.8-1~jammy1`.
```

- [ ] **Step 4: Commit tooling**

```bash
cd /home/cyberpunk/asus
git add dput.cf scripts/upload-ppa.sh docs/launchpad-setup.md
git commit -m "$(cat <<'EOF'
Phase 2c Task 4: Launchpad PPA tooling and setup guide

dput.cf: configures ppa:malila/asusctl-ubuntu as upload target.
upload-ppa.sh: signs source package with debsign and uploads via dput.
launchpad-setup.md: one-time account + GPG setup walkthrough.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Complete Launchpad setup (interactive — you do this)**

Follow `docs/launchpad-setup.md` steps 1–7. This creates the Launchpad account, PPA, and GPG key. None of these steps require code changes.

- [ ] **Step 6: First PPA upload (after CI is green and Launchpad setup complete)**

Build fresh source packages for both distros:

```bash
cd /home/cyberpunk/asus
# Delete cached tarballs to rebuild clean
rm -f packages/asusctl/build/asusctl_*.orig.tar.xz
rm -f packages/supergfxctl/build/supergfxctl_*.orig.tar.xz
bash scripts/build-all-debs.sh
```

Upload all eight source packages (4 packages × 2 distros):

```bash
for pkg in asus-backlight-fix asusctl supergfxctl asusctl-suite; do
    bash scripts/upload-ppa.sh "$pkg" jammy
    bash scripts/upload-ppa.sh "$pkg" noble
done
```

Wait for build emails from Launchpad (~10–20 min each). Verify the PPA page at:
`https://launchpad.net/~malila/+archive/ubuntu/asusctl-ubuntu`

All four packages should show green build status for both jammy and noble.

- [ ] **Step 7: Smoke-test the PPA**

On your ASUS Jammy machine:

```bash
sudo add-apt-repository ppa:malila/asusctl-ubuntu
sudo apt update
sudo apt install asusctl-suite
asusctl --version
supergfxctl --version
```

Expected: both commands print version strings matching 6.3.8 and 5.2.7.

---

## Task 5: User docs

**Files:**
- Create: `docs/install.md`
- Create: `docs/troubleshoot.md`

- [ ] **Step 1: Create docs/install.md**

Create `/home/cyberpunk/asus/docs/install.md`:

```markdown
# Install

## Requirements

- Ubuntu 22.04 (Jammy) or Ubuntu 24.04 (Noble)
- ASUS TUF or ROG laptop
- Terminal

## Steps

```bash
sudo add-apt-repository ppa:malila/asusctl-ubuntu
sudo apt update
sudo apt install asusctl-suite
reboot
```

## Quick reference

```bash
# Power profile
asusctl profile set Quiet
asusctl profile set Balanced
asusctl profile set Performance

# Keyboard backlight
asusctl leds set off
asusctl leds set low
asusctl leds set med
asusctl leds set high

# Battery charge limit
asusctl battery limit 80      # cap at 80%
asusctl battery limit 100     # no cap

# GPU mode (reboot required after switch)
supergfxctl -g                # show current mode
supergfxctl -m Hybrid         # iGPU + dGPU on demand (default)
supergfxctl -m Dedicated      # dGPU only
supergfxctl -m Integrated     # iGPU only (lowest power)
```

## Uninstall

```bash
sudo apt purge asusctl-suite asusctl supergfxctl asus-backlight-fix
sudo add-apt-repository --remove ppa:malila/asusctl-ubuntu
```
```

- [ ] **Step 2: Create docs/troubleshoot.md**

Create `/home/cyberpunk/asus/docs/troubleshoot.md`:

```markdown
# Troubleshoot

## Services not starting

```bash
systemctl status asusd
journalctl -u asusd -n 50
```

If `asusd` fails with "module not found" errors, the `asus-nb-wmi` kernel
module is not loaded. This module is built into Ubuntu kernels for most ASUS
laptops — verify your kernel version:

```bash
uname -r
modinfo asus-nb-wmi
```

If the module exists but is not loaded:
```bash
sudo modprobe asus-nb-wmi
sudo systemctl restart asusd
```

Stale config from a previous manual install can also cause failures. Remove it:
```bash
sudo rm -rf /etc/asusd/
sudo systemctl restart asusd
```

## Backlight fix not activating (FA507NV / FA507 family)

The `asus-backlight-fix` package runs hardware detection in its `postinst`
script. Verify it activated:

```bash
ls /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf
```

If the file is missing, re-run the postinst:
```bash
sudo dpkg-reconfigure asus-backlight-fix
sudo update-initramfs -u
reboot
```

## GPU mode not switching

```bash
supergfxctl -g
systemctl status supergfxd
journalctl -u supergfxd -n 50
```

If `nvidia-prime` is installed alongside `supergfxctl`, both tools manage GPU
switching. Use only one. To check:
```bash
dpkg -l nvidia-prime
```

GPU mode switches require a reboot — `supergfxctl` does not hot-switch.

## Battery charge limit ignored

```bash
cat /sys/class/power_supply/BAT0/charge_control_end_threshold
systemctl status asusd
```

If `battery-charge-threshold.service` is still running (pre-existing manual
service), disable it — `asusctl`'s postinst should have done this at install:

```bash
systemctl status battery-charge-threshold.service
sudo systemctl disable --now battery-charge-threshold.service
asusctl battery limit 80
```
```

- [ ] **Step 3: Commit**

```bash
cd /home/cyberpunk/asus
git add docs/install.md docs/troubleshoot.md
git commit -m "$(cat <<'EOF'
Phase 2c Task 5: user docs (install.md + troubleshoot.md)

Terminal-first install guide and four-issue troubleshoot reference.
Provisional — will be updated as the project matures.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Notes

- Task 1 Step 7 deletes the cached orig tarball before verifying vendor; actually the vendor step only runs when the tarball doesn't exist yet, so the first run is fine.
- Tasks 1 and 2 both replace `build-source-package.sh`. Task 2's version is the final one; Task 1's intermediate version is intentionally without the DISTRO param.
- `upload-ppa.sh` uses `dput --config` to point at the repo's `dput.cf` rather than the system-wide `~/.dput.cf` — avoids polluting the user's global dput config.
- The `debsign` call in `upload-ppa.sh` will prompt for the GPG passphrase interactively.
