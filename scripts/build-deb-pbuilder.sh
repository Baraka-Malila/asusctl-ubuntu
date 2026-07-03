#!/usr/bin/env bash
# Phase 2b: build a binary .deb in a Jammy pbuilder chroot.
#   Usage: scripts/build-deb-pbuilder.sh <pkgname> [--direct]
#
# --direct: bypass pbuilder and build on the host via dpkg-buildpackage.
#   Use this for Rust packages that require a newer toolchain than Jammy's
#   pbuilder chroot provides (rustc < 1.82 in Jammy's universe repo).
#   Phase 2c will address this with a vendor tarball or a Rust backports hook.
set -euo pipefail

PKGNAME="${1:?usage: $0 <pkgname> [--direct]}"
DIRECT=0
[ "${2:-}" = "--direct" ] && DIRECT=1

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/packages/$PKGNAME/build"
DSC=$(ls "$BUILD_DIR"/*.dsc 2>/dev/null | head -1)
[ -n "$DSC" ] || { echo "ERROR: no .dsc under $BUILD_DIR — run build-source-package.sh first" >&2; exit 1; }

if [ "$DIRECT" = "1" ]; then
    echo "==> Direct host build for $DSC (bypassing pbuilder)"
    STAGE="$BUILD_DIR/stage-direct"
    rm -rf "$STAGE" && mkdir -p "$STAGE"
    (cd "$STAGE" && dpkg-source -x "../$(basename "$DSC")" src)
    # -d: skip build-dep check (rustc/cargo are via rustup, not dpkg packages)
    (cd "$STAGE/src" && PATH="$HOME/.cargo/bin:$PATH" dpkg-buildpackage -b --no-sign -d)
    mv "$STAGE"/*.deb "$BUILD_DIR/" 2>/dev/null || true
    mv "$STAGE"/*.buildinfo "$BUILD_DIR/" 2>/dev/null || true
    rm -rf "$STAGE"
else
    echo "==> pbuilder build for $DSC"
    echo '381011' | sudo -S pbuilder build --configfile "$REPO_ROOT/pbuilderrc" \
        --buildresult "$BUILD_DIR" "$DSC"
fi

echo "==> Resulting artifacts in $BUILD_DIR:"
ls -la "$BUILD_DIR"/*.deb 2>&1
