# minPi

Minimal, RAM-resident Linux distribution for Raspberry Pi. The entire system
boots from a single read-only FAT32 partition into an initramfs and runs
entirely from RAM. Nothing writes to the SD card after boot.

## Supported boards

- Raspberry Pi Zero 2 W
- Raspberry Pi 3 Model A+
- Raspberry Pi 3 Model B
- Raspberry Pi 3 Model B+

All share the BCM2837 SoC (Cortex-A53, aarch64). The original Pi Zero and
Zero W are ARMv6 and are not supported.

## What's in the image

| Component | Size | Source |
|---|---|---|
| Linux kernel 6.12 + modules | ~15MB | raspberrypi/linux, rpi-6.12.y |
| initramfs (busybox, dropbear, wpa_supplicant, iw, curl, htop, nano, ethtool, lsusb, i2c-tools, libgpiod + deps) | ~26MB | Alpine packages, cross-compiled static binaries |
| VideoCore firmware | ~5MB | raspberrypi/firmware |
| Device tree blobs (4 boards) | ~125KB | Built with kernel |
| Boot config | ~1KB | Hand-written |
| **Total image** | **~51MB** | Auto-sized to fit |

The system runs entirely from RAM after boot. The SD card can be
physically removed and the system continues running.

## Prerequisites

- [Podman](https://podman.io/) (or Docker — rename `Containerfile` to
  `Dockerfile`)
- An SD card and a way to write to it

## Building

```sh
# Build the container (once)
podman build -t minpi-build .

# Create persistent volumes for the kernel source and build output
podman volume create minpi-linux-src
podman volume create minpi-linux-out

# Fetch Raspberry Pi firmware and WiFi firmware blobs
podman run --rm -v "$(pwd)":/build minpi-build \
    sh -c '/build/scripts/fetch-firmware.sh && /build/scripts/fetch-wifi-firmware.sh'

# Build the kernel (~5-10 minutes first time)
podman run --rm \
    -v "$(pwd)":/build \
    -v minpi-linux-src:/build/linux \
    -v minpi-linux-out:/build/linux-out \
    minpi-build /build/scripts/build-kernel.sh

# Build the initramfs and SD card image
podman run --rm -v "$(pwd)":/build minpi-build \
    sh -c '/build/scripts/build-initramfs.sh && /build/scripts/build-image.sh'
```

## Flashing

```sh
dd if=minpi.img of=/dev/sdX bs=4M status=progress
```

## Connecting

HDMI + USB keyboard:

```
login: root
(no password)
```

Over the network (Pi 3B/3B+ with ethernet, or WiFi if configured):

```sh
ssh root@<ip-address>
```

## Customizing

See [CUSTOMIZATION.md](CUSTOMIZATION.md) for runtime config persistence,
adding packages, WiFi setup, kernel modules, and more.

## Design

See [CLAUDE.md](CLAUDE.md) for the full architecture document, design
principles, and phase plan.
