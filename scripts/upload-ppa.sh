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
dput --config "$REPO_ROOT/dput.cf" malila-arch-asusctl \
    "$STAGE"/*_source.changes

rm -rf "$STAGE"
echo "==> Done. Launchpad will email bmalila87@gmail.com when the build completes."
