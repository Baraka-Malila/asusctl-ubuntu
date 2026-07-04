# Troubleshoot

## Services not starting

```bash
systemctl status asusd
journalctl -u asusd -n 50
```

If `asusd` fails with "module not found" errors, the `asus-nb-wmi` kernel
module is not loaded. This module is built into Ubuntu kernels for most ASUS
laptops — verify your kernel version:

```bash
uname -r
modinfo asus-nb-wmi
```

If the module exists but is not loaded:
```bash
sudo modprobe asus-nb-wmi
sudo systemctl restart asusd
```

Stale config from a previous manual install can also cause failures. Remove it:
```bash
sudo rm -rf /etc/asusd/
sudo systemctl restart asusd
```

## Backlight fix not activating (FA507NV / FA507 family)

The `asus-backlight-fix` package runs hardware detection in its `postinst`
script. Verify it activated:

```bash
ls /etc/modprobe.d/asusctl-fa507nv-backlight-fix.conf
```

If the file is missing, re-run the postinst:
```bash
sudo dpkg-reconfigure asus-backlight-fix
sudo update-initramfs -u
reboot
```

## GPU mode not switching

```bash
supergfxctl -g
systemctl status supergfxd
journalctl -u supergfxd -n 50
```

If `nvidia-prime` is installed alongside `supergfxctl`, both tools manage GPU
switching. Use only one. To check:
```bash
dpkg -l nvidia-prime
```

GPU mode switches require a reboot — `supergfxctl` does not hot-switch.

## Battery charge limit ignored

```bash
cat /sys/class/power_supply/BAT0/charge_control_end_threshold
systemctl status asusd
```

If `battery-charge-threshold.service` is still running (pre-existing manual
service), disable it — `asusctl`'s postinst should have done this at install:

```bash
systemctl status battery-charge-threshold.service
sudo systemctl disable --now battery-charge-threshold.service
asusctl battery limit 80
```
