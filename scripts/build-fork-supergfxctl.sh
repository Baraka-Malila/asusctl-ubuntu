#!/usr/bin/env bash
# Phase 1 Task 3: reproducible build of our supergfxctl fork.
# Same shape as build-fork-asusctl.sh. Phase 0 built from tag 5.2.7 (verified
# via git describe on upstream/supergfxctl). Task 8 will decide whether we
# ship supergfxd separately or rely on the copy asusd-6.3.8 vendors as a git
# dep — for now we keep the tree so patches (e.g. Task 7 udev) have a home.
set -euo pipefail

BASE_TAG="${SUPERGFXCTL_BASE_TAG:-5.2.7}"
UPSTREAM_URL="https://gitlab.com/asus-linux/supergfxctl.git"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO_ROOT/fork/supergfxctl"
SERIES="$REPO_ROOT/patches/supergfxctl/series"
PATCH_DIR="$REPO_ROOT/patches/supergfxctl"

mkdir -p "$REPO_ROOT/fork" "$PATCH_DIR"
touch "$SERIES"

if [ ! -d "$DEST/.git" ]; then
    echo "==> Cloning supergfxctl into fork/supergfxctl"
    git clone "$UPSTREAM_URL" "$DEST"
    git -C "$DEST" checkout "tags/$BASE_TAG" -b "fork/base"
else
    git -C "$DEST" fetch --tags --force
fi

echo "==> Resetting fork/supergfxctl to fork/base (tag $BASE_TAG)"
git -C "$DEST" checkout fork/base
git -C "$DEST" branch -D fork/applied 2>/dev/null || true
git -C "$DEST" checkout -b fork/applied

count=0
while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in \#*) continue ;; esac
    echo "==> Applying patches/supergfxctl/$p"
    git -C "$DEST" am "$PATCH_DIR/$p"
    count=$((count+1))
done < "$SERIES"
echo "==> $count patch(es) applied"

echo "==> cargo build --release"
source "$HOME/.cargo/env"
(cd "$DEST" && cargo build --release)

echo "==> Built binaries:"
ls -la "$DEST"/target/release/supergfxd "$DEST"/target/release/supergfxctl
