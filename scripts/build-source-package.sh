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
