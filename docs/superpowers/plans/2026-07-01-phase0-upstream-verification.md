# Phase 0 — Upstream Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify OGC `asusctl` v1.0.1 and `supergfxctl` (latest tag) build and function correctly on the ASUS TUF Gaming A15 FA507NV before committing to package them for Ubuntu. Output is a verification report that decides which features ship in v0.1.

**Architecture:** Investigative work, not TDD. Each task defines acceptance criteria for a feature, runs it via the upstream CLI/daemon, records pass/fail/quirks in a growing verification report at `docs/superpowers/verification/2026-07-01-phase0-report.md`. GPU mode switching gets extra safety protocol due to the documented NVIDIA ACPI hotplug crash risk on this hardware.

**Tech Stack:** Rust (rustup, cargo, rustc ≥ 1.82), Linux kernel 6.8 with `asus-nb-wmi`, systemd, dbus, FA507NV hardware. Ubuntu 22.04 host.

## Global Constraints

- File length hard limit: 300 lines (CLAUDE.md rule 1). Not likely to bite in Phase 0.
- Real hardware only — no VMs (CLAUDE.md testing rule). Live USB acceptable for GPU switch tests if needed.
- Never break the daily driver (CLAUDE.md philosophy).
- Existing FA507NV state must be preserved: `/etc/modprobe.d/nvidia-custom.conf`, `/etc/systemd/system/battery-charge-threshold.service`, kernel cmdline params. Do not modify.
- Every task commits incrementally to `main` and pushes to `origin`.
- Any daemon we run for testing is stopped and disabled at end of Phase 0. We are not installing daemons long-term in Phase 0.
- Upstream source lives in `upstream/` (gitignored). We do not commit upstream code to this repo.
- Verification report path: `docs/superpowers/verification/2026-07-01-phase0-report.md`.

---

## Files & Structure

**Created in this plan:**

- `scripts/setup-dev.sh` — installs rustc/cargo/build deps
- `scripts/fetch-upstream-asusctl.sh` — clones OGC asusctl at v1.0.1
- `scripts/fetch-upstream-supergfxctl.sh` — clones OGC supergfxctl at latest tag
- `scripts/gpu-switch-safety-net.sh` — journal follow + snapshot helper for GPU switch tests
- `docs/superpowers/verification/2026-07-01-phase0-report.md` — growing verification report
- `upstream/` (directory, gitignored)

**Modified in this plan:**

- `.gitignore` — add `upstream/` and script cache dirs

---

## Pre-flight state snapshot (before Task 1)

Before touching anything, capture current machine state so we can compare and rollback:

```bash
mkdir -p /tmp/asus-phase0-snapshot
cat /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy > /tmp/asus-phase0-snapshot/thermal_policy 2>/dev/null || echo "n/a" > /tmp/asus-phase0-snapshot/thermal_policy
cat /sys/class/power_supply/BAT1/charge_control_end_threshold > /tmp/asus-phase0-snapshot/charge_threshold 2>/dev/null || echo "n/a" > /tmp/asus-phase0-snapshot/charge_threshold
systemctl list-units --type=service --state=running | grep -Ei 'asus|nvidia|super' > /tmp/asus-phase0-snapshot/running_services 2>&1
lsmod | grep -Ei 'asus|nvidia' > /tmp/asus-phase0-snapshot/loaded_modules 2>&1
cp /etc/modprobe.d/nvidia-custom.conf /tmp/asus-phase0-snapshot/ 2>/dev/null || true
ls /tmp/asus-phase0-snapshot/
```

This snapshot is the ground truth for rollback verification at Task 17.

---

### Task 1: Development environment setup

**Files:**
- Create: `scripts/setup-dev.sh`

**Consumes:** Nothing.

**Produces:** A working Rust toolchain (rustc ≥ 1.82, cargo) and apt build deps installed system-wide. Script is idempotent and safe to re-run.

- [ ] **Step 1: Write `scripts/setup-dev.sh`**

```bash
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
```

- [ ] **Step 2: Make it executable and run it**

```bash
chmod +x scripts/setup-dev.sh
./scripts/setup-dev.sh
```

Expected: Script completes without error. Final line reads "Dev environment ready."

- [ ] **Step 3: Verify Rust version**

```bash
source "$HOME/.cargo/env"
rustc --version
```

Expected: `rustc 1.82.x` or later.

- [ ] **Step 4: Commit**

```bash
git add scripts/setup-dev.sh
git commit -m "Add dev environment setup script (Rust + build deps)"
git push
```

---

### Task 2: Fetch OGC asusctl v1.0.1 source

**Files:**
- Create: `scripts/fetch-upstream-asusctl.sh`
- Modify: `.gitignore` (add `upstream/`)
- Create: `upstream/asusctl/` (gitignored, populated by script)

**Consumes:** Task 1's Rust toolchain (not directly, but the workflow assumes it).

**Produces:** `upstream/asusctl/` checked out to tag `v1.0.1` from `github.com/OpenGamingCollective/asusctl`.

- [ ] **Step 1: Update `.gitignore`**

Append to `.gitignore`:

```
# Upstream source (fetched by scripts, not committed)
upstream/
```

- [ ] **Step 2: Write `scripts/fetch-upstream-asusctl.sh`**

```bash
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
```

- [ ] **Step 3: Run the fetch script**

```bash
chmod +x scripts/fetch-upstream-asusctl.sh
./scripts/fetch-upstream-asusctl.sh
```

Expected: Final line reads `Current HEAD: v1.0.1`.

- [ ] **Step 4: Confirm tag and file structure**

```bash
git -C upstream/asusctl describe --tags
ls upstream/asusctl
```

Expected: `v1.0.1`. Directory contains `Cargo.toml`, `asusd/`, `asusctl/`, `distro-packaging/`.

- [ ] **Step 5: Commit**

```bash
git add .gitignore scripts/fetch-upstream-asusctl.sh
git commit -m "Add asusctl upstream fetch script (pinned v1.0.1)"
git push
```

---

### Task 3: Build asusctl from source

**Files:**
- Create: `docs/superpowers/verification/2026-07-01-phase0-report.md`

**Consumes:** Task 1 (Rust toolchain), Task 2 (upstream/asusctl at v1.0.1).

**Produces:** `upstream/asusctl/target/release/asusd` and `upstream/asusctl/target/release/asusctl` binaries. First entry in verification report: build success/failure with any warnings.

- [ ] **Step 1: Create the verification report skeleton**

Create `docs/superpowers/verification/2026-07-01-phase0-report.md`:

```markdown
# Phase 0 Verification Report — asusctl-ubuntu

**Test hardware:** ASUS TUF Gaming A15 FA507NV
**Kernel:** (fill in from `uname -r`)
**BIOS:** FA507NV.316
**Date:** 2026-07-01

## Build Results

### asusctl v1.0.1

*(filled in by Task 3)*

## Feature Verification

*(filled in by Tasks 5-15)*

## Recommended Actions for v0.1

*(filled in by Task 16)*
```

- [ ] **Step 2: Build asusctl in release mode**

```bash
source "$HOME/.cargo/env"
cd upstream/asusctl
cargo build --release 2>&1 | tee /tmp/asusctl-build.log
cd ../..
```

Expected: `Finished release [optimized]` at the end. If it fails, record the exact error in the verification report and install any missing deps found in the error message.

- [ ] **Step 3: Verify binaries exist**

```bash
ls -la upstream/asusctl/target/release/asusd upstream/asusctl/target/release/asusctl
file upstream/asusctl/target/release/asusd
```

Expected: Both files exist, both are ELF 64-bit executables.

- [ ] **Step 4: Record build results in the report**

Edit `docs/superpowers/verification/2026-07-01-phase0-report.md` and fill in the "asusctl v1.0.1" section under "Build Results" with:

- Rust version used
- Build duration (from `time` prefix if you added one, otherwise estimate)
- Warnings count from build log
- Any errors encountered and how they were resolved

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: asusctl v1.0.1 build verification"
git push
```

---

### Task 4: Install asusd for testing (from source build)

**Files:** None modified in repo. This task installs upstream artifacts to system paths temporarily.

**Consumes:** Task 3's built binaries.

**Produces:** `asusd` daemon running as a systemd service and registered on the system dbus. Feature test tasks (5-8) depend on this.

**Rollback:** Task 17 stops, disables, and removes all installed files.

- [ ] **Step 1: Install binaries to /usr/local**

Note: We deliberately use `/usr/local` here because these are non-packaged test binaries. Per CLAUDE.md rule 8, `.deb` packages must NOT use `/usr/local` — but this is a raw source install, not a package. It comes out cleanly in Task 17.

```bash
sudo install -m 755 upstream/asusctl/target/release/asusd /usr/local/sbin/asusd
sudo install -m 755 upstream/asusctl/target/release/asusctl /usr/local/bin/asusctl
```

- [ ] **Step 2: Install systemd unit and dbus policy from upstream tree**

```bash
sudo install -m 644 upstream/asusctl/data/asusd.service /etc/systemd/system/asusd-test.service
sudo sed -i 's|ExecStart=.*|ExecStart=/usr/local/sbin/asusd|' /etc/systemd/system/asusd-test.service
sudo install -m 644 upstream/asusctl/data/asusd.conf /etc/dbus-1/system.d/asusd-test.conf 2>/dev/null || \
    echo "NOTE: dbus config may be elsewhere in upstream — check upstream/asusctl/data/ and upstream/asusctl/asusd/data/"
```

If the dbus config isn't at that path, run `find upstream/asusctl -name '*.conf' -path '*dbus*'` and install the correct one.

- [ ] **Step 3: Reload systemd and dbus, start asusd-test**

```bash
sudo systemctl daemon-reload
sudo systemctl reload dbus
sudo systemctl start asusd-test.service
sleep 2
sudo systemctl status asusd-test.service --no-pager
```

Expected: `active (running)`.

- [ ] **Step 4: Verify dbus registration**

```bash
gdbus introspect --system --dest org.asuslinux.Daemon --object-path /org/asuslinux 2>&1 | head -20
```

Expected: dbus introspection output showing interfaces. If it fails with "not provided by any .service files", the dbus config wasn't installed correctly — go back to Step 2.

- [ ] **Step 5: Record installation notes in verification report**

Add to the report under a new subsection "asusd runtime install notes" — any deviations from upstream paths encountered.

- [ ] **Step 6: Commit report update**

```bash
git add docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: asusd runtime install notes"
git push
```

---

### Task 5: Verify thermal profile feature

**Files:** Modify verification report only.

**Consumes:** Task 4 (asusd running).

**Produces:** Recorded findings on whether `asusctl profile` correctly switches thermal policy on FA507NV, and whether the kernel sysfs value follows.

**Manual verification required:** Fan behavior changes are audible/tactile — user must confirm.

- [ ] **Step 1: Snapshot current thermal policy**

```bash
cat /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy
```

Record the value (0/1/2) in the verification report as "starting state."

- [ ] **Step 2: List available profiles via asusctl**

```bash
asusctl profile -l
```

Expected: Output lists `Balanced`, `Performance`, `Quiet` (or similar).

- [ ] **Step 3: Switch to Performance**

```bash
asusctl profile -P Performance
sleep 1
cat /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy
```

Expected sysfs value: `0` (or whatever upstream defines for Performance). Fan noise should increase within a few seconds under any CPU load.

- [ ] **Step 4: Switch to Quiet**

```bash
asusctl profile -P Quiet
sleep 1
cat /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy
```

Expected sysfs value: `2`. Fan noise should decrease audibly.

- [ ] **Step 5: Switch to Balanced (restore)**

```bash
asusctl profile -P Balanced
cat /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy
```

- [ ] **Step 6: Record findings in report**

Under "Feature Verification → Thermal Profiles":

- Which profile names asusctl exposes
- Whether sysfs value follows for each
- Whether fan noise change is audible (user confirms)
- Any errors, warnings, or delays

- [ ] **Step 7: Commit**

```bash
git add docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: thermal profile verification"
git push
```

---

### Task 6: Verify fan curve feature

**Files:** Modify verification report only.

**Consumes:** Task 4 (asusd running).

**Produces:** Recorded findings on fan curve read (definitely) and write (if hardware supports).

- [ ] **Step 1: Read current fan curve**

```bash
asusctl fan-curve -g
```

Expected: Output shows fan curve points (temperature → PWM percentage) for CPU and GPU fans, or an error indicating not supported on this model.

Record the raw output (or error) in the report.

- [ ] **Step 2: Read fan RPM sysfs**

```bash
cat /sys/class/hwmon/hwmon*/fan*_input 2>/dev/null
cat /sys/class/hwmon/hwmon*/name 2>/dev/null
```

Record which hwmon devices expose fan RPMs.

- [ ] **Step 3: Attempt to write a custom fan curve (conservative)**

Only proceed if Step 1 returned a curve (didn't error). Use a conservative curve that ramps fans up moderately:

```bash
asusctl fan-curve -m Balanced -f cpu -D "30c:20%,50c:40%,70c:70%,80c:100%"
asusctl fan-curve -g
```

Expected: New curve shows in the read-back.

- [ ] **Step 4: Restore default curve**

```bash
asusctl fan-curve -m Balanced --enabled false
```

- [ ] **Step 5: Record findings**

Under "Feature Verification → Fan Curves":

- Read supported? Y/N + output
- Write supported? Y/N + which mode/fan
- Any errors or model-specific messages

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: fan curve verification"
git push
```

---

### Task 7: Verify keyboard backlight feature

**Files:** Modify verification report only.

**Consumes:** Task 4 (asusd running).

**Produces:** Recorded findings on keyboard backlight brightness control.

**Manual verification required:** Backlight change is visual — user must confirm.

- [ ] **Step 1: Get current backlight state**

```bash
asusctl -k
```

Or the equivalent per upstream CLI. If uncertain, check `asusctl --help` for the correct flag.

- [ ] **Step 2: Cycle brightness levels**

```bash
asusctl -k low
sleep 1
asusctl -k med
sleep 1
asusctl -k high
sleep 1
asusctl -k off
sleep 1
asusctl -k med
```

User visually confirms brightness changes at each step.

- [ ] **Step 3: Record findings**

Under "Feature Verification → Keyboard Backlight":

- CLI flags that worked
- Whether each brightness level is visually distinct
- Any errors

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: keyboard backlight verification"
git push
```

---

### Task 8: Verify battery charge threshold feature

**Files:** Modify verification report only.

**Consumes:** Task 4 (asusd running).

**Produces:** Recorded findings on battery charge threshold read/write and interaction with existing `battery-charge-threshold.service`.

**Critical:** This machine has an existing systemd unit setting threshold to 80%. Do not fight it — coexist.

- [ ] **Step 1: Read current threshold from sysfs and via asusctl**

```bash
cat /sys/class/power_supply/BAT1/charge_control_end_threshold
asusctl -c
# or whatever upstream flag maps to charge threshold read
```

Record both values in the report.

- [ ] **Step 2: Check the existing systemd unit is still active**

```bash
systemctl status battery-charge-threshold.service --no-pager
```

Expected: `active (exited)` or similar. Do not disturb this unit.

- [ ] **Step 3: Test asusctl setting the threshold to a different value**

```bash
asusctl -c 85
sleep 1
cat /sys/class/power_supply/BAT1/charge_control_end_threshold
```

Expected: sysfs value changes to 85 (or whatever asusctl wrote).

- [ ] **Step 4: Restore to 80 to match existing unit's intent**

```bash
asusctl -c 80
cat /sys/class/power_supply/BAT1/charge_control_end_threshold
```

- [ ] **Step 5: Record findings**

Under "Feature Verification → Battery Charge Threshold":

- Whether asusctl reads/writes the same sysfs the existing unit does
- Whether the existing unit's value persists after asusctl writes (it should — write is one-shot)
- Any conflict between asusctl and the existing service

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: battery charge threshold verification"
git push
```

---

### Task 9: Fetch and build OGC supergfxctl

**Files:**
- Create: `scripts/fetch-upstream-supergfxctl.sh`

**Consumes:** Task 1 (Rust toolchain).

**Produces:** `upstream/supergfxctl/` checked out to the latest stable tag, and `upstream/supergfxctl/target/release/supergfxd` + `supergfxctl` binaries built.

Note: Per Phase 0 research, the OGC repo has no `debian/` but may have `supergfxctl` bundled or in a separate repo. The engineer should first check if OGC's asusctl repo contains supergfxctl, then fall back to searching for a separate OGC supergfxctl repo, then the archived gitlab tag if needed.

- [ ] **Step 1: Write `scripts/fetch-upstream-supergfxctl.sh`**

```bash
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
```

- [ ] **Step 2: Run the fetch script**

```bash
chmod +x scripts/fetch-upstream-supergfxctl.sh
./scripts/fetch-upstream-supergfxctl.sh
```

Record which upstream source succeeded (OGC or GitLab) and the tag pinned. Note it in the verification report under "Upstream sources."

- [ ] **Step 3: Build supergfxctl**

```bash
source "$HOME/.cargo/env"
cd upstream/supergfxctl
cargo build --release 2>&1 | tee /tmp/supergfxctl-build.log
cd ../..
```

Expected: `Finished release [optimized]`. Record any warnings or errors in the report.

- [ ] **Step 4: Verify binaries**

```bash
ls -la upstream/supergfxctl/target/release/supergfxd upstream/supergfxctl/target/release/supergfxctl
```

- [ ] **Step 5: Commit script and report update**

```bash
git add scripts/fetch-upstream-supergfxctl.sh docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: supergfxctl fetch script and build verification"
git push
```

---

### Task 10: Install supergfxd for testing

**Files:** None modified in repo. Installs binaries + systemd unit to system paths.

**Consumes:** Task 9 (supergfxctl binaries built).

**Produces:** `supergfxd` running as `supergfxd-test.service`, registered on dbus.

- [ ] **Step 1: Install binaries**

```bash
sudo install -m 755 upstream/supergfxctl/target/release/supergfxd /usr/local/sbin/supergfxd
sudo install -m 755 upstream/supergfxctl/target/release/supergfxctl /usr/local/bin/supergfxctl
```

- [ ] **Step 2: Locate and install systemd unit + dbus policy from upstream tree**

```bash
find upstream/supergfxctl -name 'supergfxd.service' -o -name 'supergfxd*.conf'
```

Install the systemd unit as `supergfxd-test.service` (edit ExecStart to `/usr/local/sbin/supergfxd`) and the dbus config to `/etc/dbus-1/system.d/supergfxd-test.conf`.

- [ ] **Step 3: Configure supergfxd for gdm3 display manager**

Locate upstream's `supergfxd.conf` (config file, not dbus policy) and install it to `/etc/supergfxd.conf`, editing the display manager entry to `gdm3` (Ubuntu default).

- [ ] **Step 4: Reload systemd + dbus, start supergfxd-test**

```bash
sudo systemctl daemon-reload
sudo systemctl reload dbus
sudo systemctl start supergfxd-test.service
sleep 2
sudo systemctl status supergfxd-test.service --no-pager
```

Expected: `active (running)`.

- [ ] **Step 5: Commit report update**

```bash
git add docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: supergfxd runtime install notes"
git push
```

---

### Task 11: Verify GPU mode read (safe, no state change)

**Files:** Modify verification report only.

**Consumes:** Task 10 (supergfxd running).

**Produces:** Recorded findings on `supergfxctl -g` (get current mode) working correctly. No state changes attempted.

- [ ] **Step 1: Read current GPU mode**

```bash
supergfxctl -g
```

Expected: Output like `Hybrid`, `Integrated`, or `Dedicated`. Record the value.

- [ ] **Step 2: Read supported modes**

```bash
supergfxctl -s
```

Expected: List of modes this hardware supports.

- [ ] **Step 3: Verify NVIDIA modules currently loaded**

```bash
lsmod | grep -E 'nvidia|nouveau'
```

This snapshots the current kernel state before any GPU switch test.

- [ ] **Step 4: Record findings**

Under "Feature Verification → GPU Mode (read-only)":

- Current mode reported by supergfxctl
- Modes it says are supported
- Kernel modules loaded

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: GPU mode read-only verification"
git push
```

---

### Task 12: Prepare GPU switch safety net

**Files:**
- Create: `scripts/gpu-switch-safety-net.sh`

**Consumes:** Nothing.

**Produces:** A helper script that tails kernel logs during a GPU switch and snapshots relevant state before/after.

**CRITICAL SAFETY NOTE:** The NVIDIA ACPI hotplug crash pattern on this machine (see memory / project_nvidia_crash_pattern.md) can produce full system LOCKUP during GPU state transitions under load. Existing modprobe fixes at `/etc/modprobe.d/nvidia-custom.conf` mitigate but do not eliminate the risk. Task 13 gates further action on the executor's judgment call about testing venue (installed system vs live USB).

- [ ] **Step 1: Write `scripts/gpu-switch-safety-net.sh`**

```bash
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
```

- [ ] **Step 2: Make executable and test 'pre'**

```bash
chmod +x scripts/gpu-switch-safety-net.sh
./scripts/gpu-switch-safety-net.sh pre baseline
ls /tmp/asus-gpu-snapshots/pre-baseline/
```

Expected: Snapshot files present (`modules`, `mode`, `nvidia-smi`, `dmesg_tail`, `timestamp`).

- [ ] **Step 3: Commit**

```bash
git add scripts/gpu-switch-safety-net.sh
git commit -m "Add GPU switch safety net helper (snapshot + monitor)"
git push
```

---

### Task 13: Test GPU mode switching (with safety protocol)

**Files:** Modify verification report only.

**Consumes:** Task 10 (supergfxd running), Task 12 (safety net script).

**Produces:** Recorded findings on whether GPU mode switching works on FA507NV, including any crash or instability observed.

**SAFETY PROTOCOL — MUST FOLLOW:**

1. Machine must be on **AC power** during every switch test.
2. Save all work in other applications; expect potential need to reboot.
3. Open a second SSH session from another device (phone/laptop) to this machine — this is the escape hatch if the display fails to come back.
4. Run `./scripts/gpu-switch-safety-net.sh monitor` in a second terminal (log follower).
5. If ANY switch produces a display glitch that doesn't recover within 30 seconds, stop and record it as a FAIL. Do not chain more switches.

**Executor judgment call:** If confidence is low, do this task from a live USB Ubuntu 22.04 boot instead of the installed system. Note in the report which venue was used.

- [ ] **Step 1: Pre-switch snapshot**

```bash
./scripts/gpu-switch-safety-net.sh pre hybrid-to-integrated
```

- [ ] **Step 2: Switch Hybrid → Integrated**

```bash
supergfxctl -m Integrated
```

Expected: Command may take up to 30 seconds. Display may flicker or briefly turn off. It should recover.

If the display does NOT recover within 60 seconds, use the SSH escape hatch: `sudo systemctl restart gdm3`. If that also fails, `sudo reboot`. Record the failure and stop.

- [ ] **Step 3: Post-switch snapshot and confirmation**

```bash
./scripts/gpu-switch-safety-net.sh post hybrid-to-integrated
supergfxctl -g
lsmod | grep -Ei 'nvidia|nouveau'
```

Expected mode: `Integrated`. Expected: `nvidia` modules unloaded, only iGPU driver present.

- [ ] **Step 4: Test workload on iGPU**

Open a simple GL app (e.g. `glxgears` or `glxinfo | grep 'OpenGL renderer'`) and verify it runs on the AMD iGPU. Record the renderer string.

- [ ] **Step 5: Pre-switch snapshot for reverse direction**

```bash
./scripts/gpu-switch-safety-net.sh pre integrated-to-hybrid
```

- [ ] **Step 6: Switch Integrated → Hybrid**

```bash
supergfxctl -m Hybrid
```

Same wait window as Step 2. Same escape protocol.

- [ ] **Step 7: Post-switch verify**

```bash
./scripts/gpu-switch-safety-net.sh post integrated-to-hybrid
supergfxctl -g
lsmod | grep nvidia
```

Expected mode: `Hybrid`. Expected: `nvidia` modules loaded again.

- [ ] **Step 8: Record findings comprehensively**

Under "Feature Verification → GPU Mode Switching":

- Testing venue (installed system or live USB)
- Each direction tested: Hybrid→Integrated, Integrated→Hybrid — pass/fail/quirks
- Time each switch took
- Any log warnings or errors from the safety net snapshots
- Whether the display recovered cleanly
- If crash occurred: full description and recovery steps used
- Verdict: is GPU switching safe to ship in v0.1 on this machine?

- [ ] **Step 9: Commit**

```bash
git add docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: GPU mode switching verification (with safety protocol)"
git push
```

---

### Task 14: Battery-power testing pass

**Files:** Modify verification report only.

**Consumes:** Tasks 5-8 (features verified on AC).

**Produces:** Recorded findings on whether each verified asusctl feature behaves the same on battery.

**Not repeating GPU switching on battery** — the AC/battery ACPI transition itself is the crash trigger. Battery-power GPU switching is deferred to a future test with better tooling.

- [ ] **Step 1: Unplug AC power. Confirm on battery.**

```bash
cat /sys/class/power_supply/AC/online
```

Expected: `0` (off AC).

- [ ] **Step 2: Re-run thermal profile switches**

Repeat Task 5 Steps 2-5 briefly. Record any differences from AC behavior.

- [ ] **Step 3: Re-run fan curve read**

Repeat Task 6 Step 1. Record if output differs.

- [ ] **Step 4: Re-run keyboard backlight cycle**

Repeat Task 7 Step 2 briefly.

- [ ] **Step 5: Re-check battery threshold reads correctly**

Repeat Task 8 Step 1.

- [ ] **Step 6: Plug AC back in**

Confirm no crash on transition (this is the risky bit). Record.

- [ ] **Step 7: Record findings**

Under "Feature Verification → Battery-power behavior":

- Which features behaved identically to AC
- Any differences
- Whether the AC-reconnect transition was clean (critical for our crash pattern documentation)

- [ ] **Step 8: Commit**

```bash
git add docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: battery-power feature verification"
git push
```

---

### Task 15: GPU-load testing pass

**Files:** Modify verification report only.

**Consumes:** Tasks 5-8 (features verified on AC idle).

**Produces:** Recorded findings on whether features remain responsive with the dGPU under load.

- [ ] **Step 1: Start a GPU workload**

Option A (if you have a game installed): launch it.
Option B (safer, headless): run a stress workload:

```bash
# glmark2 stresses GPU nicely and is available in apt
sudo apt install -y glmark2
glmark2 &
GLM_PID=$!
sleep 10
```

Verify nvidia-smi shows GPU utilization > 20%.

- [ ] **Step 2: While workload runs, exercise features**

Cycle thermal profiles (`asusctl profile -P Performance`), read fan curve, cycle keyboard backlight. Note any lag or errors.

- [ ] **Step 3: Read fan RPM under load**

```bash
cat /sys/class/hwmon/hwmon*/fan*_input
```

Expected: RPM values >> idle RPMs, confirming fans spun up.

- [ ] **Step 4: Stop workload**

```bash
kill $GLM_PID
```

- [ ] **Step 5: Record findings**

Under "Feature Verification → GPU-load behavior":

- Features that remained responsive under load
- Any lag or errors
- Whether thermal profile switch during load felt immediate or delayed

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: GPU-load feature verification"
git push
```

---

### Task 16: Write Phase 0 verdict and v0.1 recommendations

**Files:** Modify verification report only.

**Consumes:** All previous tasks' findings.

**Produces:** A clear, structured "Recommended Actions for v0.1" section that decides:

- Which features SHIP in v0.1 (verified working)
- Which features are DEFERRED (broken, risky, or need upstream patch)
- Which upstream patches we plan to submit (with issue numbers if any)
- Any Ubuntu-specific config we now know is needed

- [ ] **Step 1: Populate the "Recommended Actions for v0.1" section**

Fill it in with the structure:

```markdown
## Recommended Actions for v0.1

### Features cleared to ship

- [ ] `asusctl` thermal profile switching — verdict, notes
- [ ] `asusctl` fan curves — verdict, notes
- [ ] `asusctl` keyboard backlight — verdict, notes
- [ ] `asusctl` battery threshold — verdict, notes
- [ ] `supergfxctl` GPU mode switching — verdict, notes

### Features deferred to v0.2+

*(list with reasons)*

### Upstream patches to submit

*(list, with target issue/PR numbers if we opened any)*

### Ubuntu-specific findings

- Existing `battery-charge-threshold.service` coexists with asusctl (or does not)
- `/etc/modprobe.d/nvidia-custom.conf` interacts with supergfxctl in *[way]*
- gdm3 config for supergfxd verified at `/etc/supergfxd.conf`

### Go/No-Go for v0.1

*(explicit statement: proceed with v0.1 packaging, YES or NO. If NO, what needs to change first.)*
```

- [ ] **Step 2: Commit final verdict**

```bash
git add docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: verdict and v0.1 recommendations"
git push
```

---

### Task 17: Teardown and rollback

**Files:** None modified in repo.

**Consumes:** All test-installed binaries and units from Tasks 4 and 10.

**Produces:** Machine restored to pre-Phase 0 state. All test binaries and units removed. Rollback verified against the pre-flight snapshot.

- [ ] **Step 1: Stop and disable test services**

```bash
sudo systemctl stop asusd-test.service supergfxd-test.service 2>/dev/null || true
sudo systemctl disable asusd-test.service supergfxd-test.service 2>/dev/null || true
```

- [ ] **Step 2: Remove installed test files**

```bash
sudo rm -f /usr/local/sbin/asusd /usr/local/sbin/supergfxd
sudo rm -f /usr/local/bin/asusctl /usr/local/bin/supergfxctl
sudo rm -f /etc/systemd/system/asusd-test.service /etc/systemd/system/supergfxd-test.service
sudo rm -f /etc/dbus-1/system.d/asusd-test.conf /etc/dbus-1/system.d/supergfxd-test.conf
sudo rm -f /etc/supergfxd.conf
sudo systemctl daemon-reload
sudo systemctl reload dbus
```

- [ ] **Step 3: Verify original state restored**

```bash
# Thermal policy back to baseline
diff <(cat /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy) /tmp/asus-phase0-snapshot/thermal_policy && echo "thermal OK"

# Battery threshold back to baseline
diff <(cat /sys/class/power_supply/BAT1/charge_control_end_threshold) /tmp/asus-phase0-snapshot/charge_threshold && echo "battery OK"

# NVIDIA modprobe untouched
diff /etc/modprobe.d/nvidia-custom.conf /tmp/asus-phase0-snapshot/nvidia-custom.conf && echo "modprobe OK"

# Original battery-charge-threshold.service still enabled
systemctl is-enabled battery-charge-threshold.service
```

Expected: All diffs empty, all "OK" messages printed, battery service still `enabled`.

If ANY check fails, restore from snapshot BEFORE marking this task complete.

- [ ] **Step 4: Record rollback verification in report**

Add final section "Post-Phase 0 rollback verification" to the report — all checks passed / any anomalies.

- [ ] **Step 5: Final commit and push**

```bash
git add docs/superpowers/verification/2026-07-01-phase0-report.md
git commit -m "Phase 0: teardown complete, rollback verified"
git push
```

---

## Phase 0 completion criteria

- All 17 tasks marked complete.
- Verification report is comprehensive and committed.
- The "Go/No-Go for v0.1" section has an explicit verdict.
- Machine is fully restored to pre-Phase 0 state (rollback verified).
- No open changes to system files, no test daemons running.

Once complete, Plan 2 (`v0.1 Ubuntu packaging`) is written based on the Phase 0 findings and executed next.
