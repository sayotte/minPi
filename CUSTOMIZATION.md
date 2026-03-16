# Customizing minPi

## Table of Contents

- [Overview](#overview)
- [Persisting runtime changes](#persisting-runtime-changes)
- [Adding packages](#adding-packages)
  - [Overlay packages (per-device)](#overlay-packages-per-device)
  - [Base packages (distro-wide)](#base-packages-distro-wide)
- [Running something at boot](#running-something-at-boot)
- [WiFi](#wifi)
- [Static IP](#static-ip)
- [Time](#time)
- [SSH access](#ssh-access)
- [Kernel](#kernel)
  - [Changing the kernel config](#changing-the-kernel-config)
  - [Building out-of-tree modules](#building-out-of-tree-modules)
- [Rebuilding the image](#rebuilding-the-image)

## Overview

minPi has three layers of customization:

1. **Runtime overlay** — edit files on the running system, persist with a
   single command. Changes are tracked automatically via overlayfs. Best for
   per-device config (hostname, WiFi credentials, static IPs).

2. **Overlay packages** — add Alpine Linux packages to the `overlay/`
   directory. Installed per-device at boot. Best for device-specific software
   that isn't part of every minPi image.

3. **Base system** — edit the `initramfs/` tree directly and rebuild. Changes
   apply to every device flashed with the resulting image. Best for distro-wide
   additions (new base packages, init scripts, kernel config).

## Persisting runtime changes

minPi uses overlayfs on `/etc`. The base system's `/etc` is the read-only
lower layer; a tmpfs is the writable upper layer. Any changes you make at
runtime (editing configs, adding files) are automatically captured in the
upper layer.

### Saving changes

```sh
# Edit whatever you need
vi /etc/hostname
vi /etc/wpa_supplicant.conf

# Persist all changes to the boot partition
mount -o remount,rw /boot
tar czf /boot/overlay.gz -C /tmp/.overlay/etc-upper .
mount -o remount,ro /boot
```

Or simply reboot — `fake-hwclock-save` runs at shutdown and saves both the
clock and the overlay automatically.

### How it works

On boot, rcS:
1. Mounts the boot partition read-only at `/boot`
2. If `/boot/overlay.gz` exists, extracts it into the overlay upper layer
3. Mounts overlayfs on `/etc` (lower=base, upper=your changes)
4. Runs init scripts from the merged `/etc/init.d/`

The upper layer contains **only** files you changed or added — never base
system files.

### Resetting to defaults

```sh
mount -o remount,rw /boot
rm /boot/overlay.gz
mount -o remount,ro /boot
# Reboot — system reverts to base image
```

### Caveat: deleted files

If you delete a base system file through the overlay (e.g.
`rm /etc/some-base-file`), overlayfs creates a "whiteout" marker in the upper
layer. Standard `tar` does not preserve whiteout markers. On the next boot,
the deleted file will reappear from the base system.

To permanently suppress a base system file, either:
- Remove it from `initramfs/etc/` and rebuild the image, or
- Add an init script early in the boot sequence (e.g. `S01-cleanup`) that
  deletes the file on every boot with `rm`

## Adding packages

### Overlay packages (per-device)

Use `add-overlay-package.sh` to add Alpine Linux packages to the `overlay/`
directory. These are packed into `overlay.gz` at image build time and applied
at boot.

```sh
podman run --rm -v "$(pwd)":/build minpi-build \
    /build/scripts/add-overlay-package.sh python3

podman run --rm -v "$(pwd)":/build minpi-build \
    /build/scripts/build-image.sh
```

### Base packages (distro-wide)

Use `add-base-package.sh` to add packages to the `initramfs/` tree. These
become part of every image built from this tree.

```sh
podman run --rm -v "$(pwd)":/build minpi-build \
    /build/scripts/add-base-package.sh python3

podman run --rm -v "$(pwd)":/build minpi-build \
    sh -c '/build/scripts/build-initramfs.sh && /build/scripts/build-image.sh'
```

Both scripts resolve shared library dependencies automatically. The musl
dynamic linker is included in the base image, so Alpine's dynamically linked
binaries work out of the box.

## Running something at boot

Init scripts live in `initramfs/etc/init.d/`. They are plain shell scripts
executed in alphabetical order by `rcS`.

The naming convention is `S<NN>-<name>`, where `<NN>` controls ordering:

| Range | Purpose                | Examples          |
|-------|------------------------|-------------------|
| 02    | Module loading         | S02-modules       |
| 05    | Console setup          | S05-console       |
| 10    | Networking             | S10-network       |
| 15    | Time sync              | S15-ntpd          |
| 20    | System services        | S20-syslog        |
| 30    | Infrastructure daemons | S30-dropbear      |
| 90-99 | Application layer      | S99-app           |

To add a new service:

1. Create `initramfs/etc/init.d/S<NN>-myservice`:

   ```sh
   #!/bin/sh
   case "$1" in
   start)
       /bin/myapp --daemon
       ;;
   esac
   ```

2. Make it executable: `chmod 755 initramfs/etc/init.d/S<NN>-myservice`

3. Rebuild the initramfs, or add it via the overlay.

## WiFi

WiFi firmware blobs are fetched by `scripts/fetch-wifi-firmware.sh` and placed
in `initramfs/lib/firmware/brcm/`.

To connect, create `/etc/wpa_supplicant.conf` (see the `.example` file) —
either in the overlay or directly in the initramfs. The network init script
automatically starts `wpa_supplicant` and runs DHCP on `wlan0` if the config
exists.

## Static IP

Create `/etc/network.conf` (see `.example` file) with:

```
INTERFACE=eth0
ADDRESS=192.168.1.100
NETMASK=24
GATEWAY=192.168.1.1
DNS=192.168.1.1
DOMAIN=example.com
```

If this file exists, the matching interface gets a static configuration
instead of DHCP. Other interfaces still use DHCP.

## Time

The Pi has no battery-backed real-time clock. minPi handles this with:

- **fake-hwclock**: saves the current time to `/boot/fake-hwclock.data` at
  shutdown, restores it on next boot.
- **ntpd**: busybox NTP daemon starts after networking. Configure servers in
  `/etc/ntp.conf` (one `server <host>` per line) or accept the defaults
  (`pool.ntp.org`, `time.google.com`).

## SSH access

Dropbear starts on port 22. On first boot it generates host keys (stored in
RAM — they change every reboot). Root login with no password is enabled by
default for initial setup.

To add an authorized key, place it in
`initramfs/etc/dropbear/authorized_keys` before building, or add it via the
overlay.

To disable password login, remove the empty password hash from
`initramfs/etc/shadow` (set it to `!` or `*`).

## Kernel

### Changing the kernel config

The kernel starts from the Raspberry Pi Foundation's `bcm2711_defconfig` with
subsystems progressively disabled in `scripts/build-kernel.sh`. To enable a
feature:

1. Edit the disable/enable lines in `scripts/build-kernel.sh`.
2. Rebuild:

   ```sh
   podman run --rm \
       -v "$(pwd)":/build \
       -v minpi-linux-src:/build/linux \
       -v minpi-linux-out:/build/linux-out \
       minpi-build /build/scripts/build-kernel.sh
   ```

3. Then rebuild the initramfs and image.

The resolved `.config` is saved to `kernel/config` after each build for
reference.

### Building out-of-tree modules

Loadable kernel modules are supported. The base kernel build installs its
modules to `initramfs/lib/modules/`.

To build an out-of-tree module:

```sh
podman run --rm \
    -v "$(pwd)":/build \
    -v minpi-linux-src:/build/linux \
    -v minpi-linux-out:/build/linux-out \
    minpi-build /build/scripts/build-module.sh /build/my-driver/
```

The module source directory must contain a standard kernel module `Makefile`.
Copy the resulting `.ko` to `initramfs/lib/modules/<version>/extra/` and
rebuild. To load at boot, add the module name to `/etc/modules`.

## Rebuilding the image

After changes to `initramfs/` or `overlay/`:

```sh
podman run --rm -v "$(pwd)":/build minpi-build \
    sh -c '/build/scripts/build-initramfs.sh && /build/scripts/build-image.sh'

# Flash
dd if=minpi.img of=/dev/sdX bs=4M status=progress
```

If you only changed files in `overlay/`, you only need `build-image.sh`.
