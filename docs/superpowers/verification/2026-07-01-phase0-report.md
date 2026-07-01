# Phase 0 Verification Report — asusctl-ubuntu

**Test hardware:** ASUS TUF Gaming A15 FA507NV
**Kernel:** 6.8.0-124-generic
**BIOS:** FA507NV.316
**Date:** 2026-07-01

## Build Results

### asusctl v1.0.1

**Rust version:** rustc 1.93.1 (01f6ddf75 2026-02-11)

**Build outcome:** SUCCESS

**Build duration:** 26.15 seconds

**Build warnings:** 2 (both from asus-nb-ctrl: field `kbd_node` never read in CtrlKbdBacklight, one unused warning from err-derive)

**Build command:**
```bash
cd upstream/asusctl
cargo build --release
```

**Binaries produced:**

1. `target/release/asusd` (1,434,776 bytes)
   - ELF 64-bit LSB pie executable, x86-64, dynamically linked
   - BuildID: 8475072e356a1338cb388d70656f61de3256daf2

2. `target/release/asusctl` (778,008 bytes)
   - ELF 64-bit LSB pie executable, x86-64, dynamically linked
   - BuildID: e1fe1348f2501b9459cd2f1ffe24f47b22c3676c

**Status:** Both binaries are valid ELF 64-bit executables, ready for testing.

## Feature Verification

*(filled in by Tasks 5-15)*

## Recommended Actions for v0.1

*(filled in by Task 16)*
