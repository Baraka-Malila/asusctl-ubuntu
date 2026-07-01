#!/usr/bin/env bash
# GPU switch safety helper.
# Usage: ./scripts/gpu-switch-safety-net.sh [pre|monitor|post] <label>
#   pre <label>     — snapshot state before a switch
#   monitor         — tail journal + nvidia-smi in a loop (run in a second terminal)
#   post <label>    — snapshot state after a switch, diff against pre
set -euo pipefail

SNAP_DIR="/tmp/asus-gpu-snapshots"
mkdir -p "$SNAP_DIR"

snapshot() {
    local label="$1"
    local out="$SNAP_DIR/$label"
    mkdir -p "$out"
    lsmod | grep -Ei 'nvidia|nouveau|amdgpu' > "$out/modules" || true
    supergfxctl -g > "$out/mode" 2>&1 || true
    nvidia-smi -q > "$out/nvidia-smi" 2>&1 || echo "nvidia-smi unavailable" > "$out/nvidia-smi"
    dmesg | tail -100 > "$out/dmesg_tail"
    date > "$out/timestamp"
    echo "==> Snapshot saved: $out"
}

case "${1:-}" in
    pre)   snapshot "pre-${2:-unnamed}" ;;
    post)
        snapshot "post-${2:-unnamed}"
        echo "==> Diff modules:"
        diff "$SNAP_DIR/pre-${2:-unnamed}/modules" "$SNAP_DIR/post-${2:-unnamed}/modules" || true
        echo "==> Mode transition:"
        echo "  pre:  $(cat "$SNAP_DIR/pre-${2:-unnamed}/mode")"
        echo "  post: $(cat "$SNAP_DIR/post-${2:-unnamed}/mode")"
        ;;
    monitor)
        echo "==> Tailing journal (Ctrl-C to stop)"
        journalctl -f -k -u supergfxd-test.service
        ;;
    *)
        echo "Usage: $0 {pre|post} <label>  |  $0 monitor"
        exit 1
        ;;
esac
