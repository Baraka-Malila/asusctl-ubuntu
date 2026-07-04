#!/usr/bin/env bash
# Build source + binary for all four packages, for both jammy and noble.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

for DISTRO in jammy noble; do
    for pkg in asus-backlight-fix asusctl supergfxctl asusctl-suite; do
        echo "===== $pkg ($DISTRO) ====="
        ./scripts/build-source-package.sh "$pkg" "$DISTRO"
        ./scripts/build-deb-pbuilder.sh   "$pkg" "$DISTRO" --direct
    done
done

echo "==> All packages built. Artifacts:"
find packages/*/build -maxdepth 2 -name '*.deb' | sort
