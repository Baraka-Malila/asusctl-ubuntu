# Phase 2b Task 2 — `asus-backlight-fix.deb` verification on FA507NV

**Date:** 2026-07-03
**Version:** `asus-backlight-fix_1.0~jammy1_all.deb` (2.5 KB)
**Format:** `3.0 (native)` (design bug corrected: `3.0 (quilt)` from the plan requires an upstream tarball; own-source packages must use native)

## Build

Source: `dpkg-source -b stage` produced `asus-backlight-fix_1.0~jammy1.dsc` + `.tar.xz`.
Binary: `pbuilder build --configfile pbuilderrc` on Jammy chroot. ~1 min build.

## Lintian

```
W: asus-backlight-fix: debian-changelog-has-wrong-day-of-week 2026-07-04 is a Saturday
```

One warning (calendar mismatch — cosmetic). Zero errors. Ships.

## Deviations from the plan (fixes in-execution)

1. **`3.0 (quilt)` → `3.0 (native)`.** Quilt requires an upstream `.orig.tar.xz`. Since this package has no upstream, native is the right format. Version format also updated: `1.0-1~jammy1` → `1.0~jammy1` (native versions cannot have a Debian-revision suffix).
2. **Removed `debian/compat`.** Modern `debhelper-compat (= 12)` in Build-Depends is the sole compat declaration; a separate `debian/compat` file causes `dh: error: debhelper compat level specified both in debian/compat and via build-dependency`.
3. **Detection heuristic simplified.** Plan checked `lsmod | grep -q "^nvidia_wmi_ec_backlight"`. Discovered on FA507NV that Phase 1's manual blacklist is already active — the module isn't loaded but `nvidia_0` is *still* registered by the main NVIDIA driver. Correct heuristic is "both `amdgpu_bl*` and `nvidia_0` present" — the actual race condition signature, not a specific module state.
4. **File shipping model changed.** Plan shipped `asusctl-fa507nv-backlight-fix.conf.disabled` directly to `/etc/modprobe.d/`. Lintian errors on `.disabled` extension in `modprobe.d`. Replaced with the standard "template in `/usr/share`, install to `/etc` conditionally" idiom:
   - Ships: `/usr/share/asus-backlight-fix/nvidia_wmi_ec_backlight-blacklist.conf`
   - Postinst on matching hardware: `cp $TEMPLATE /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf` + `update-initramfs -u`
   - Postrm: `rm /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf` + `update-initramfs -u`

## Install (activation path — race pattern present)

```
$ sudo dpkg -i asus-backlight-fix_1.0~jammy1_all.deb
Setting up asus-backlight-fix (1.0~jammy1) ...
asus-backlight-fix: activated (FA507NV-family hardware detected). Reboot to apply.
Processing triggers for initramfs-tools (0.140ubuntu13.5) ...
update-initramfs: Generating /boot/initrd.img-6.8.0-124-generic
```

Post-install:
- `/etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf` — present
- `/usr/share/asus-backlight-fix/nvidia_wmi_ec_backlight-blacklist.conf` — present
- Initramfs regenerated — will take effect on next reboot

## Purge (rollback)

```
$ sudo apt-get purge -y asus-backlight-fix
Removing asus-backlight-fix (1.0~jammy1) ...
update-initramfs: Generating /boot/initrd.img-6.8.0-124-generic
Purging configuration files for asus-backlight-fix (1.0~jammy1) ...
```

Post-purge:
- `/etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf` — absent
- `/usr/share/asus-backlight-fix/` — absent
- Initramfs regenerated — modprobe blacklist not applied on next reboot

## Not verified in this task (out of scope)

- **Skip path on non-affected hardware.** FA507NV matches the race pattern here. Phase 2c CI or a follow-up user report on ROG / Intel / non-NVIDIA hardware families will exercise it.
- **Effect after reboot.** Blacklist applies on next boot. Not rebooting mid-Phase-2b task.

## Verdict

Ships.
