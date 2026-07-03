#!/usr/bin/env bash
# Phase 2b: build a binary .deb in a Jammy pbuilder chroot.
#   Usage: scripts/build-deb-pbuilder.sh <pkgname>
set -euo pipefail

PKGNAME="${1:?usage: $0 <pkgname>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/packages/$PKGNAME/build"
DSC=$(ls "$BUILD_DIR"/*.dsc 2>/dev/null | head -1)
[ -n "$DSC" ] || { echo "ERROR: no .dsc under $BUILD_DIR — run build-source-package.sh first" >&2; exit 1; }

echo "==> pbuilder build for $DSC"
sudo pbuilder build --configfile "$REPO_ROOT/pbuilderrc" \
    --buildresult "$BUILD_DIR" "$DSC"

echo "==> Resulting artifacts in $BUILD_DIR:"
ls -la "$BUILD_DIR"/*.deb 2>&1
