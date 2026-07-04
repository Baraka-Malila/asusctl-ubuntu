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
