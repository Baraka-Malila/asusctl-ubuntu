# Install

## Requirements

- Ubuntu 22.04 (Jammy) or Ubuntu 24.04 (Noble)
- ASUS TUF or ROG laptop
- Terminal

## Steps

```bash
sudo add-apt-repository ppa:malila-arch/asusctl-ubuntu
sudo apt update
sudo apt install asusctl-suite
reboot
```

## Quick reference

```bash
# Power profile
asusctl profile set Quiet
asusctl profile set Balanced
asusctl profile set Performance

# Keyboard backlight
asusctl leds set off
asusctl leds set low
asusctl leds set med
asusctl leds set high

# Battery charge limit
asusctl battery limit 80      # cap at 80%
asusctl battery limit 100     # no cap

# GPU mode (reboot required after switch)
supergfxctl -g                # show current mode
supergfxctl -m Hybrid         # iGPU + dGPU on demand (default)
supergfxctl -m Dedicated      # dGPU only
supergfxctl -m Integrated     # iGPU only (lowest power)
```

## Uninstall

```bash
sudo apt purge asusctl-suite asusctl supergfxctl asus-backlight-fix
sudo add-apt-repository --remove ppa:malila-arch/asusctl-ubuntu
```
