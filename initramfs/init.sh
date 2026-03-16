#!/bin/sh
# PID 1 — set up overlay root, then exec busybox init

# Mount virtual filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t tmpfs tmpfs /tmp

# Set up full-root overlayfs:
# Copy initramfs into a tmpfs as the read-only lower layer,
# create a writable upper layer, mount overlay, switch_root into it.
# After this, any runtime change is captured in the upper layer.

mkdir -p /tmp/.lower /tmp/.overlay

# Copy initramfs to lower layer
mount -t tmpfs tmpfs /tmp/.lower
cp -a /bin /sbin /etc /lib /root /var /tmp/.lower/ 2>/dev/null
mkdir -p /tmp/.lower/dev /tmp/.lower/proc /tmp/.lower/sys \
         /tmp/.lower/tmp /tmp/.lower/boot /tmp/.lower/mnt \
         /tmp/.lower/run
[ -d /usr ] && cp -a /usr /tmp/.lower/

# Create upper layer
mount -t tmpfs tmpfs /tmp/.overlay
mkdir -p /tmp/.overlay/upper /tmp/.overlay/work

# Mount boot partition and restore saved overlay into upper layer
mount -t vfat -o ro /dev/mmcblk0p1 /tmp/.lower/boot 2>/dev/null
if [ -f /tmp/.lower/boot/overlay.gz ]; then
    echo "Restoring overlay..."
    tar xzf /tmp/.lower/boot/overlay.gz -C /tmp/.overlay/upper 2>/dev/null
fi

# Mount the overlay
mkdir -p /mnt
mount -t overlay overlay \
    -o lowerdir=/tmp/.lower,upperdir=/tmp/.overlay/upper,workdir=/tmp/.overlay/work \
    /mnt

# Move mounts into the new root
mount --move /tmp/.lower/boot /mnt/boot 2>/dev/null
mount --move /tmp/.overlay /mnt/tmp/.overlay 2>/dev/null
mount --move /tmp/.lower /mnt/tmp/.lower 2>/dev/null

# Unmount virtual filesystems (switch_root needs them unmounted)
umount /proc
umount /sys
umount /dev

# Switch to the overlay root and start busybox init
exec switch_root /mnt /sbin/init
