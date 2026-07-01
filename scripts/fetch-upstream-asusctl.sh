#!/usr/bin/env bash
# Fetches OGC asusctl at the pinned tag into upstream/asusctl.
# Idempotent: re-running updates the working tree to the pinned tag.
set -euo pipefail

UPSTREAM_URL="https://github.com/OpenGamingCollective/asusctl.git"
UPSTREAM_TAG="v1.0.1"
DEST_DIR="upstream/asusctl"

mkdir -p upstream

if [ ! -d "$DEST_DIR/.git" ]; then
    echo "==> Cloning $UPSTREAM_URL into $DEST_DIR"
    git clone "$UPSTREAM_URL" "$DEST_DIR"
fi

echo "==> Fetching tags"
git -C "$DEST_DIR" fetch --tags --force

echo "==> Checking out tag $UPSTREAM_TAG"
git -C "$DEST_DIR" checkout "tags/$UPSTREAM_TAG"

echo "==> Current HEAD: $(git -C "$DEST_DIR" describe --tags)"
