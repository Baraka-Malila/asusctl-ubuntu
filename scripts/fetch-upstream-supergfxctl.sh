#!/usr/bin/env bash
# Fetches supergfxctl into upstream/supergfxctl.
# Tries OGC first, falls back to archived GitLab if needed.
set -euo pipefail

DEST_DIR="upstream/supergfxctl"
OGC_URL="https://github.com/OpenGamingCollective/supergfxctl.git"
FALLBACK_URL="https://gitlab.com/asus-linux/supergfxctl.git"

mkdir -p upstream

if [ ! -d "$DEST_DIR/.git" ]; then
    echo "==> Trying OGC clone"
    if git clone "$OGC_URL" "$DEST_DIR" 2>/dev/null; then
        echo "==> Cloned from OGC"
    else
        echo "==> OGC failed, trying archived GitLab"
        git clone "$FALLBACK_URL" "$DEST_DIR"
    fi
fi

echo "==> Fetching tags"
git -C "$DEST_DIR" fetch --tags --force

LATEST_TAG="$(git -C "$DEST_DIR" tag --sort=-v:refname | head -1)"
echo "==> Latest tag: $LATEST_TAG"

git -C "$DEST_DIR" checkout "tags/$LATEST_TAG"
echo "==> Current HEAD: $(git -C "$DEST_DIR" describe --tags)"
