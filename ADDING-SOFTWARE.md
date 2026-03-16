# Adding Software to minPi

## How the image works

The entire root filesystem lives in `initramfs/`. At build time,
`build-initramfs.sh` packs that directory tree into `initramfs.cpio.gz`, which
the kernel extracts into RAM at boot. After boot, the SD card is never touched.

To change what's on the system, you edit the `initramfs/` tree and rebuild.

## Adding Alpine packages (easiest)

Use `add-package.sh` to pull pre-built Alpine Linux packages directly into the
initramfs. This automatically includes the musl dynamic linker.

```sh
podman run --rm -v .:/build minpi-build \
    /build/scripts/add-package.sh python3 curl htop
```

Then rebuild:

```sh
podman run --rm -v .:/build minpi-build \
    sh -c '/build/scripts/build-initramfs.sh && /build/scripts/build-image.sh'
```

Packages are extracted into the initramfs tree (`/usr/bin/`, `/usr/lib/`, etc.)
and included in the next image build. Dependencies are resolved automatically
(one level deep).

The musl dynamic linker is included in the base image, so Alpine's dynamically
linked binaries work out of the box.

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

To load a module at boot, add `modprobe <name>` to an init script.

## Running something at boot

Init scripts live in `initramfs/etc/init.d/`. They are plain shell scripts
executed in alphabetical order by `rcS`.

The naming convention is `S<NN>-<name>`, where `<NN>` controls ordering:

| Range | Purpose              | Examples          |
|-------|----------------------|-------------------|
| 05    | Console setup        | S05-console       |
| 10    | Networking           | S10-network       |
| 20    | System services      | S20-syslog        |
| 30    | Infrastructure daemons | S30-dropbear    |
| 90-99 | Application layer    | S99-app           |

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

3. Rebuild the initramfs.

## Adding configuration files

Drop them anywhere under `initramfs/etc/`. They end up at the same path on the
running system. For example, `initramfs/etc/myapp.conf` becomes `/etc/myapp.conf`.

## WiFi

WiFi firmware blobs are fetched by `scripts/fetch-wifi-firmware.sh` and placed
in `initramfs/lib/firmware/brcm/`.

To connect, create `/etc/wpa_supplicant.conf` (see the `.example` file) before
building. The network init script will automatically start `wpa_supplicant` and
run DHCP on `wlan0` if the config file exists.

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
`initramfs/etc/dropbear/authorized_keys` before building.

To disable password login, remove the empty password hash from
`initramfs/etc/shadow` (set it to `!` or `*`).
