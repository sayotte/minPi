# Adding Software to minPi

## How the image works

The entire root filesystem lives in `initramfs/`. At build time,
`build-initramfs.sh` packs that directory tree into `initramfs.cpio.gz`, which
the kernel extracts into RAM at boot. After boot, the SD card is never touched.

To change what's on the system, you edit the `initramfs/` tree and rebuild.

## Adding a binary

All binaries must be **statically linked** (or linked against musl). There is no
glibc, no dynamic linker, and no package manager on the running system.

1. Cross-compile your program for aarch64 with `-static`:

   ```sh
   aarch64-linux-gnu-gcc -static -o myapp myapp.c
   ```

   Or build inside the container:

   ```sh
   podman run --rm -v .:/build minpi-build \
       aarch64-linux-gnu-gcc -static -o /build/initramfs/bin/myapp /build/src/myapp.c
   ```

2. Place the binary in `initramfs/bin/` or `initramfs/sbin/`.

3. If the build is non-trivial, add it as a step in `scripts/build-initramfs.sh`
   so it's reproducible from a clean checkout.

## Running something at boot

Init scripts live in `initramfs/etc/init.d/`. They are plain shell scripts
executed in alphabetical order by `rcS`.

The naming convention is `S<NN>-<name>`, where `<NN>` controls ordering:

| Range | Purpose              | Examples          |
|-------|----------------------|-------------------|
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

## WiFi firmware

The brcmfmac driver needs firmware blobs in the initramfs at
`/lib/firmware/brcm/`. The required files depend on the board:

- Zero 2 W: `brcmfmac43436-sdio.bin`, `brcmfmac43436-sdio.clm_blob`,
  `brcmfmac43436-sdio.txt`
- Pi 3B: `brcmfmac43430-sdio.bin`, `brcmfmac43430-sdio.txt`
- Pi 3B+: `brcmfmac43455-sdio.bin`, `brcmfmac43455-sdio.clm_blob`,
  `brcmfmac43455-sdio.txt`

These can be copied from the
[linux-firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/tree/brcm)
repository into `initramfs/lib/firmware/brcm/`.

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

1. Edit `kernel/config.fragment` — add the `CONFIG_*` symbols you need.
2. Rebuild the kernel:

   ```sh
   podman run --rm -v .:/build -v minpi-linux-src:/build/linux \
       minpi-build /build/scripts/build-kernel.sh
   ```

3. Then rebuild the image as above.

The resolved `.config` is saved to `kernel/config` after each build for
reference, but `kernel/config.fragment` is the source of truth.

## SSH access

Dropbear starts on port 22. On first boot it generates host keys (stored in
RAM — they change every reboot). Root login with no password is enabled by
default for initial setup.

To add an authorized key, place it in
`initramfs/etc/dropbear/authorized_keys` before building.

To disable password login, remove the empty password hash from
`initramfs/etc/shadow` (set it to `!` or `*`).
