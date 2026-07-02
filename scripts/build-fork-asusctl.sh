#!/usr/bin/env bash
# Phase 1 Task 3: reproducible build of our asusctl fork.
# Clones OGC asusctl at the base tag into fork/asusctl/ (if not present), then
# resets to fork/base and applies every patch listed in patches/asusctl/series
# in order. With empty series this is a vanilla upstream build.
#
# Override the base tag with ASUSCTL_BASE_TAG=... in the environment.
# Task 2 chose 6.3.8 as the fork base.
set -euo pipefail

BASE_TAG="${ASUSCTL_BASE_TAG:-6.3.8}"
UPSTREAM_URL="https://github.com/OpenGamingCollective/asusctl.git"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO_ROOT/fork/asusctl"
SERIES="$REPO_ROOT/patches/asusctl/series"
PATCH_DIR="$REPO_ROOT/patches/asusctl"

mkdir -p "$REPO_ROOT/fork" "$PATCH_DIR"
touch "$SERIES"

if [ ! -d "$DEST/.git" ]; then
    echo "==> Cloning asusctl into fork/asusctl"
    git clone "$UPSTREAM_URL" "$DEST"
    git -C "$DEST" checkout "tags/$BASE_TAG" -b "fork/base"
else
    git -C "$DEST" fetch --tags --force
fi

echo "==> Resetting fork/asusctl to fork/base (tag $BASE_TAG)"
git -C "$DEST" checkout fork/base
git -C "$DEST" branch -D fork/applied 2>/dev/null || true
git -C "$DEST" checkout -b fork/applied

count=0
while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in \#*) continue ;; esac
    echo "==> Applying patches/asusctl/$p"
    git -C "$DEST" am "$PATCH_DIR/$p"
    count=$((count+1))
done < "$SERIES"
echo "==> $count patch(es) applied"

echo "==> cargo build --release"
source "$HOME/.cargo/env"
(cd "$DEST" && cargo build --release)

echo "==> Built binaries:"
ls -la "$DEST"/target/release/asusd "$DEST"/target/release/asusctl
