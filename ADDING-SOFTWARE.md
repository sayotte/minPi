# Adding Software to minPi

## How the image works

The entire root filesystem lives in `initramfs/`. At build time,
`build-initramfs.sh` packs that directory tree into a compressed archive, which
the kernel extracts into RAM at boot. After boot, the SD card is never touched
(the boot partition is mounted read-only at `/boot`).

To change what's on the system, you edit the `initramfs/` tree and rebuild.

## Persisting changes at runtime (boot overlay)

You don't need to rebuild the image just to change a config file. minPi
supports a **boot overlay**: a tarball on the boot partition that gets extracted
over `/` early in the boot process (before networking, before services).

### Making a change

On the running Pi:

```sh
# Edit whatever you need
vi /etc/wpa_supplicant.conf
vi /etc/hostname

# Persist it to the boot partition
mount -o remount,rw /boot
tar czf /boot/overlay.gz -C / etc/wpa_supplicant.conf etc/hostname
mount -o remount,ro /boot
```

On the next boot, `S01-overlay` extracts the tarball over `/` before any
services start. You can include any files — configs, scripts, even binaries.

### Updating an existing overlay

To add files to an existing overlay without losing what's already there:

```sh
mount -o remount,rw /boot
mkdir -p /tmp/overlay
cd /tmp/overlay
tar xzf /boot/overlay.gz 2>/dev/null
# Copy in new/changed files, preserving paths
cp /etc/some-new-config etc/
tar czf /boot/overlay.gz *
cp /tmp/overlay.gz /boot/overlay.gz   # not needed, tar wrote in place
mount -o remount,ro /boot
```

### Removing the overlay

```sh
mount -o remount,rw /boot
rm /boot/overlay.gz
mount -o remount,ro /boot
```

The system reverts to the base image on next boot.

## Adding Alpine packages (easiest)

Use `add-package.sh` to pull pre-built Alpine Linux packages directly into the
initramfs. Dependencies (including shared libraries) are resolved automatically.

```sh
podman run --rm -v .:/build minpi-build \
    /build/scripts/add-package.sh python3 cups whatever-else
```

Then rebuild:

```sh
podman run --rm -v .:/build minpi-build \
    sh -c '/build/scripts/build-initramfs.sh && /build/scripts/build-image.sh'
```

Packages are extracted into the initramfs tree (`/usr/bin/`, `/usr/lib/`, etc.)
and included in the next image build. The musl dynamic linker is included in
the base image, so Alpine's dynamically linked binaries work out of the box.

**Note:** Packages added this way become part of the base image. For quick
experiments or per-device customization, consider putting the binaries in the
boot overlay instead.

## Adding a static binary

For custom software, cross-compile for aarch64 with `-static`:

```sh
aarch64-linux-gnu-gcc -static -o myapp myapp.c
```

Or build inside the container:

```sh
podman run --rm -v .:/build minpi-build \
    aarch64-linux-gnu-gcc -static -o /build/initramfs/bin/myapp /build/src/myapp.c
```

Place the binary in `initramfs/bin/` or `initramfs/sbin/`.

## Building kernel modules

Loadable kernel modules are supported. The base kernel build installs its
built-in modules to `initramfs/lib/modules/`.

To build an out-of-tree module:

```sh
podman run --rm \
    -v .:/build \
    -v minpi-linux-src:/build/linux \
    -v minpi-linux-out:/build/linux-out \
    minpi-build /build/scripts/build-module.sh /build/my-driver/
```

The module source directory must contain a standard kernel module `Makefile`.
The resulting `.ko` file will be in the source directory. Copy it to
`initramfs/lib/modules/<version>/extra/` and rebuild the image.

To load a module at boot, add its name to `/etc/modules` (one per line).

## Running something at boot

Init scripts live in `initramfs/etc/init.d/`. They are plain shell scripts
executed in alphabetical order by `rcS`.

The naming convention is `S<NN>-<name>`, where `<NN>` controls ordering:

| Range | Purpose                | Examples          |
|-------|------------------------|-------------------|
| 01    | Boot overlay           | S01-overlay       |
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

3. Rebuild the initramfs, or add it via the boot overlay.

## WiFi

WiFi firmware blobs are fetched by `scripts/fetch-wifi-firmware.sh` and placed
in `initramfs/lib/firmware/brcm/`.

To connect, create `/etc/wpa_supplicant.conf` (see the `.example` file) before
building, or add it via the boot overlay. The network init script will
automatically start `wpa_supplicant` and run DHCP on `wlan0` if the config
file exists.

## Time

The Pi has no battery-backed real-time clock. minPi handles this with:

- **fake-hwclock**: saves the current time to `/boot/fake-hwclock.data` at
  shutdown, restores it on next boot. Not accurate, but prevents the clock
  from starting at epoch.
- **ntpd**: busybox NTP daemon syncs with `pool.ntp.org` and
  `time.google.com` after networking is up.

## Rebuilding

After any change to `initramfs/`:

```sh
# Repack the initramfs (fast — seconds)
podman run --rm -v .:/build minpi-build /build/scripts/build-initramfs.sh

# Rebuild the SD card image
podman run --rm -v .:/build minpi-build /build/scripts/build-image.sh

# Flash
dd if=minpi.img of=/dev/sdX bs=4M status=progress
```

If you only changed files in `initramfs/`, you do **not** need to rebuild the
kernel. The kernel build takes minutes; the initramfs repack takes seconds.

## Updating the kernel config

If you need a new kernel feature (e.g. a driver for attached hardware):

1. Edit the disable/enable lines in `scripts/build-kernel.sh`.
2. Rebuild the kernel:

   ```sh
   podman run --rm \
       -v .:/build \
       -v minpi-linux-src:/build/linux \
       -v minpi-linux-out:/build/linux-out \
       minpi-build /build/scripts/build-kernel.sh
   ```

3. Then rebuild the image as above.

The resolved `.config` is saved to `kernel/config` after each build for
reference.

## SSH access

Dropbear starts on port 22. On first boot it generates host keys (stored in
RAM — they change every reboot). Root login with no password is enabled by
default for initial setup.

To add an authorized key, place it in
`initramfs/etc/dropbear/authorized_keys` before building, or add it via the
boot overlay.

To disable password login, remove the empty password hash from
`initramfs/etc/shadow` (set it to `!` or `*`).
