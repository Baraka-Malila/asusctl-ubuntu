#!/usr/bin/env bash
# Purge our four Debian packages in dependency-safe order (reverse-deps first).
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root" >&2; exit 1
fi
for pkg in asusctl-suite asus-backlight-fix asusctl supergfxctl; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        echo "==> Purging $pkg"
        apt-get purge -y "$pkg" || true
    fi
done
echo "==> Done"
