#!/usr/bin/env bash
set -euo pipefail
UPSTREAM_URL="https://github.com/OpenGamingCollective/asusctl.git"
TAG="6.3.8"
DEST="upstream/asusctl-638"
mkdir -p upstream
[ -d "$DEST/.git" ] || git clone "$UPSTREAM_URL" "$DEST"
git -C "$DEST" fetch --tags --force
git -C "$DEST" checkout "tags/$TAG"
echo "==> HEAD: $(git -C "$DEST" describe --tags)"
