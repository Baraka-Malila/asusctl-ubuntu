#!/usr/bin/env bash
# Installs rust toolchain (via rustup) and apt build deps for asusctl/supergfxctl.
# Idempotent — safe to re-run.
set -euo pipefail

echo "==> Installing apt build dependencies"
sudo apt update
sudo apt install -y --no-install-recommends \
    build-essential pkg-config \
    libudev-dev libclang-dev libinput-dev \
    libgtk-3-dev libgtk-4-dev \
    curl git ca-certificates

echo "==> Installing rustup (if not already installed)"
if ! command -v rustup >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
fi

echo "==> Upgrading rustup and installing stable"
rustup update stable
rustup default stable

echo "==> Verifying versions"
rustc --version
cargo --version

REQUIRED_MAJOR=1
REQUIRED_MINOR=82
CURRENT="$(rustc --version | awk '{print $2}')"
CURRENT_MAJOR="$(echo "$CURRENT" | cut -d. -f1)"
CURRENT_MINOR="$(echo "$CURRENT" | cut -d. -f2)"
if [ "$CURRENT_MAJOR" -lt "$REQUIRED_MAJOR" ] || { [ "$CURRENT_MAJOR" -eq "$REQUIRED_MAJOR" ] && [ "$CURRENT_MINOR" -lt "$REQUIRED_MINOR" ]; }; then
    echo "ERROR: rustc $CURRENT is below required $REQUIRED_MAJOR.$REQUIRED_MINOR"
    exit 1
fi
echo "==> Dev environment ready."
