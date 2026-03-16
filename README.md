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

| Component      | Size   | Source                    |
|----------------|--------|---------------------------|
| VideoCore firmware | ~5MB | raspberrypi/firmware repo |
| Linux kernel   | ~8MB   | raspberrypi/linux, rpi-6.6.y branch |
| busybox        | ~900KB | Alpine Linux static build |
| dropbear (SSH) | ~1.5MB | Cross-compiled, static    |
| Init scripts   | ~2KB   | Hand-written shell        |
| **Total image** | **~15MB** | |

## Prerequisites

- [Podman](https://podman.io/) (or Docker — rename `Containerfile` to
  `Dockerfile`)
- An SD card and a way to write to it

## Building

```sh
# Build the container (once)
podman build -t minpi-build .

# Create a persistent volume for the kernel source (avoids re-cloning)
podman volume create minpi-linux-src

# Fetch Raspberry Pi firmware blobs
podman run --rm -v .:/build minpi-build /build/scripts/fetch-firmware.sh

# Build the kernel (~5-10 minutes first time)
podman run --rm -v .:/build -v minpi-linux-src:/build/linux \
    minpi-build /build/scripts/build-kernel.sh

# Build the initramfs (busybox + dropbear + init scripts)
podman run --rm -v .:/build minpi-build /build/scripts/build-initramfs.sh

# Assemble the SD card image
podman run --rm -v .:/build minpi-build /build/scripts/build-image.sh
```

## Flashing

```sh
dd if=minpi.img of=/dev/sdX bs=4M status=progress
```

## Connecting

Serial console (via USB-to-serial adapter or HDMI + USB keyboard):

```
login: root
(no password)
```

Over the network (Pi 3B/3B+ with ethernet):

```sh
ssh root@<ip-address>
```

## Customizing

See [CUSTOMIZATION.md](CUSTOMIZATION.md) for runtime config persistence,
adding packages, WiFi setup, kernel modules, and more.

## Design

See [CLAUDE.md](CLAUDE.md) for the full architecture document, design
principles, and phase plan.
