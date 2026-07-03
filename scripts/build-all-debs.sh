#!/usr/bin/env bash
# Phase 2b: build source + binary for all four packages in dependency order.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

for pkg in asus-backlight-fix asusctl supergfxctl asusctl-suite; do
    echo "===== $pkg ====="
    ./scripts/build-source-package.sh "$pkg"
    ./scripts/build-deb-pbuilder.sh   "$pkg"
done

echo "==> All four packages built. Artifacts:"
find packages/*/build -maxdepth 1 -name '*.deb'
