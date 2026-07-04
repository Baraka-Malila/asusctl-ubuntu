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
        # Capture vendor output — it includes git-source redirects as well as crates-io
        mkdir -p "$VSTAGE/$SRCDIR/.cargo"
        (cd "$VSTAGE/$SRCDIR" && cargo vendor vendor/) \
            > "$VSTAGE/$SRCDIR/.cargo/config.toml"
        # cargo vendor creates Cargo.toml.orig beside each crate's Cargo.toml (original
        # before dep-normalization). dh_clean/dpkg-source --after-build deletes them via
        # quilt clean, but .cargo-checksum.json still lists them → cargo build fails.
        # Strip them from both the filesystem and the checksums before packaging.
        find "$VSTAGE/$SRCDIR/vendor" -name "Cargo.toml.orig" -delete
        python3 - "$VSTAGE/$SRCDIR/vendor" <<'PY'
import json, os, sys
vendor = sys.argv[1]
for crate in os.listdir(vendor):
    p = os.path.join(vendor, crate, ".cargo-checksum.json")
    if not os.path.exists(p):
        continue
    with open(p) as f:
        d = json.load(f)
    d["files"] = {k: v for k, v in d["files"].items() if not k.endswith(".orig")}
    with open(p, "w") as f:
        json.dump(d, f, separators=(",", ":"))
PY
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
