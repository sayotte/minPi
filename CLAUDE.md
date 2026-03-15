# minPi

Minimal, RAM-resident Linux distribution for Raspberry Pi. The entire system
boots from a read-only FAT32 partition into an initramfs and runs entirely from
RAM. Nothing writes to the SD card after boot.

## Design Principles

- **Appliance model, not server model.** A minPi device should boot in under 5
  seconds and be power-cycled freely, like turning off a light.
- **Nothing you didn't choose.** Every binary, every service, every file exists
  because it was explicitly included. No package manager at runtime.
- **Persistent state lives elsewhere.** Syslog goes to a remote host. App state
  goes to a remote API/database/NFS. Config changes mean rebuilding the
  initramfs and reflashing the boot partition.
- **The SD card is read-only after boot.** It could be physically removed and
  the system continues running.

## What We Don't Use

These are explicitly excluded — not because they're bad software, but because
they don't belong in a system this small:

- systemd / systemctl
- NetworkManager
- ifupdown
- dbus
- udev (devtmpfs handles device nodes; if we need rules, we write them by hand)
- glibc (musl or static binaries only)
- loadable kernel modules (CONFIG_MODULES=n)
- any package manager at runtime

## Target Hardware

Primary: **Raspberry Pi Zero 2 W** (BCM2710, aarch64, 512MB RAM)
Secondary: Pi 4 Model B (BCM2711), Pi 5 (BCM2712) — same approach, different
DTB and firmware blobs.

The Zero 2 W is the most constrained target, so if it works there, it works
everywhere.

## Architecture

### Boot Partition (FAT32, ~20MB)

```
/boot
├── start4.elf / start.elf       # VideoCore firmware (closed-source, required)
├── fixup4.dat / fixup.dat       # GPU memory fixup
├── config.txt                   # GPU firmware config
├── cmdline.txt                  # Kernel command line
├── kernel8.img                  # Custom aarch64 kernel, DTB appended
└── initramfs.cpio.gz            # The entire root filesystem
```

No second partition. No ext4. One FAT32 partition is the whole SD card.

### initramfs Contents

```
/
├── bin/busybox                  # Static musl binary, ~1.5MB, ~300 applets
├── sbin/
│   ├── init -> ../bin/busybox
│   ├── dropbear                 # Static SSH server (~110KB)
│   └── dropbearkey
├── etc/
│   ├── init.d/
│   │   ├── rcS                  # Master init script (plain shell)
│   │   ├── S10-network          # ip commands + udhcpc
│   │   ├── S20-syslog           # busybox syslogd -> remote host
│   │   ├── S30-dropbear         # SSH daemon
│   │   └── S99-app              # Application entry point
│   ├── hostname
│   ├── passwd, shadow, group
│   ├── resolv.conf
│   ├── syslog.conf              # *.* @<remote>:514
│   ├── dropbear/
│   │   └── authorized_keys
│   └── network/
│       └── interfaces           # Or empty if using udhcpc
├── dev/                         # devtmpfs mounted at boot
├── proc/
├── sys/
├── tmp/
└── var/{log,run}/               # tmpfs
```

### Init System

No service manager. `/sbin/init` is busybox init, which runs `/etc/init.d/rcS`,
which is a shell script that mounts virtual filesystems and runs numbered scripts
in order. That's it. A service is a shell script. Supervision is "if it dies, we
probably reboot."

## Build Process

### Cross-Compilation Toolchain

Pre-built from the host distro's package manager. No hand-built toolchain.

```sh
# Debian/Ubuntu
apt install gcc-aarch64-linux-gnu make flex bison bc libssl-dev
# Provides: aarch64-linux-gnu-gcc, aarch64-linux-gnu-ld, etc.
```

All kernel and userspace builds use:
```sh
ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
```

### Kernel

Source: Raspberry Pi Foundation fork (https://github.com/raspberrypi/linux),
branch `rpi-6.6.y` or latest stable.

Key config decisions:
- `CONFIG_MODULES=n` — no loadable modules, everything built-in or absent
- `CONFIG_BLK_DEV_INITRD=y` — initramfs support
- `CONFIG_SWAP=n`
- `CONFIG_CGROUPS=n` (unless we want containers later)
- GPU/DRM disabled (headless by default)
- Bluetooth disabled
- WiFi: enabled only if needed for the specific device, otherwise disabled
- Sound disabled
- Input subsystem disabled
- Filesystems: only tmpfs, proc, sysfs, devtmpfs
- DTB appended to kernel image

Target kernel size: 3-5MB uncompressed, ~2MB compressed.

### Userspace Binaries

| Binary       | Source                          | Notes                          |
|--------------|---------------------------------|--------------------------------|
| busybox      | Alpine aarch64 static package   | Or cross-compiled from source  |
| dropbear     | Cross-compiled, static, no zlib | SSH server + keygen            |
| app-specific | Whatever the device needs       | Also static or musl-linked     |

### initramfs Packing

```sh
cd initramfs/
find . | cpio -H newc -o | gzip -9 > ../initramfs.cpio.gz
```

### SD Card Assembly

```sh
# Single FAT32 partition
sudo fdisk /dev/sdX        # One partition, type 0x0C
sudo mkfs.vfat -F 32 /dev/sdX1
sudo mount /dev/sdX1 /mnt/boot
sudo cp start*.elf fixup*.dat config.txt cmdline.txt kernel8.img initramfs.cpio.gz /mnt/boot/
sudo umount /mnt/boot
```

## Development Workflow

### Directory Structure

```
minpi/
├── CLAUDE.md                    # This file
├── kernel/
│   └── config                   # Saved kernel .config
├── initramfs/
│   ├── bin/
│   ├── sbin/
│   ├── etc/
│   │   ├── init.d/
│   │   ├── dropbear/
│   │   └── network/
│   └── ...
├── boot/
│   ├── config.txt
│   └── cmdline.txt
├── scripts/
│   ├── build-kernel.sh          # Fetch source, apply config, cross-compile
│   ├── build-initramfs.sh       # Pack initramfs from initramfs/ tree
│   ├── build-image.sh           # Assemble everything onto SD card or image file
│   └── fetch-firmware.sh        # Download VideoCore blobs from RPi firmware repo
└── firmware/                    # VideoCore blobs (gitignored, fetched by script)
```

### Iteration Loop

**Fast (initramfs only):** Edit files in `initramfs/`, run `build-initramfs.sh`,
copy to SD card boot partition, reboot Pi. Turnaround: ~30 seconds.

**Slow (kernel change):** Edit kernel config, run `build-kernel.sh` (minutes),
then fast loop. Do this rarely; get userspace right first.

**Fastest (TFTP boot):** Configure Pi firmware to network-boot via TFTP over
ethernet. Build machine serves kernel + initramfs over LAN. No SD card swapping.
Zero 2 W note: TFTP boot is ethernet-only, and the Zero 2 W has no ethernet
port. You'd need a USB-to-ethernet adapter, or use the SD card loop for Zeros.

## Phase Plan

### Phase 1: Bootable baseline
- Fetch firmware blobs, kernel source
- Build kernel with minimal config for Zero 2 W
- Hand-build initramfs: busybox + init scripts + dropbear
- Boot to SSH prompt over WiFi (Zero 2 W) or ethernet (Pi 4)
- Validate: system runs entirely from RAM, SD card is not written to

### Phase 2: Build automation
- `build-kernel.sh` that fetches, configures, and cross-compiles
- `build-initramfs.sh` that packs the tree
- `build-image.sh` that creates a flashable .img file
- Reproducible from a clean checkout

### Phase 3: Remote syslog + hardening
- Configure busybox syslogd to forward all logs via UDP
- Lock down SSH (key-only, no root password)
- Verify no writes to SD card under any conditions
- Minimal /etc/passwd, no unnecessary accounts

### Phase 4: Application layer
- Whatever the specific Pi is supposed to do
- Each device "variant" is a different S99-app script and possibly
  different included binaries
- Consider: variant configs as separate directories or branches

## Notes

- The VideoCore firmware is closed-source and non-negotiable. Don't waste time
  trying to replace it. ~3MB on the boot partition.
- WiFi on the Zero 2 W requires firmware blobs loaded by the kernel
  (brcmfmac). These need to be in the initramfs at the expected path
  (`/lib/firmware/brcm/`). This is one of the bigger additions to the
  initramfs size. If ethernet is an option, prefer it.
- Alpine Linux in diskless mode is a useful reference for how this should
  feel at runtime. The goal is to arrive at something simpler than Alpine,
  not to reinvent it.
- busybox `udhcpc` needs a script at `/etc/udhcpc.script` (or specified via
  `-s` flag) to actually apply the lease. Alpine ships a good default one;
  grab it as a starting point.
- The kernel's `CONFIG_ARM64_APPENDED_DTB` or `cat Image dtb > kernel8.img`
  approach means we don't need separate .dtb files on the boot partition.
  One fewer thing to get wrong.
