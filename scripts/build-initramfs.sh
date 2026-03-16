#!/bin/sh
set -e

TOPDIR="$(cd "$(dirname "$0")/.." && pwd)"
INITRAMFS="$TOPDIR/initramfs"
OUT="$TOPDIR/initramfs.cpio.gz"

# --- Fetch static busybox (Alpine aarch64) ---
BUSYBOX="$INITRAMFS/bin/busybox"
if [ ! -f "$BUSYBOX" ]; then
    echo "Fetching static busybox from Alpine..."
    ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine/v3.19/main/aarch64"

    # Get the package index to find the current busybox-static filename
    wget -q -O /tmp/APKINDEX.tar.gz "$ALPINE_MIRROR/APKINDEX.tar.gz"
    tar -xzf /tmp/APKINDEX.tar.gz -C /tmp APKINDEX
    BB_PKG=$(awk '/^P:busybox-static$/{found=1} found && /^V:/{print "busybox-static-"substr($0,3)".apk"; exit}' /tmp/APKINDEX)

    if [ -z "$BB_PKG" ]; then
        echo "ERROR: Could not find busybox-static package in Alpine index"
        exit 1
    fi

    echo "Downloading $BB_PKG..."
    wget -q -O /tmp/busybox.apk "$ALPINE_MIRROR/$BB_PKG"
    tar -xzf /tmp/busybox.apk -C /tmp bin/busybox.static 2>/dev/null || true
    if [ -f /tmp/bin/busybox.static ]; then
        mv /tmp/bin/busybox.static /tmp/bin/busybox
    fi

    cp /tmp/bin/busybox "$BUSYBOX"
    chmod 755 "$BUSYBOX"
    rm -rf /tmp/bin /tmp/busybox.apk /tmp/APKINDEX /tmp/APKINDEX.tar.gz
    echo "busybox installed: $(ls -lh "$BUSYBOX" | awk '{print $5}')"
else
    echo "busybox already present"
fi

# --- Build static dropbear ---
DROPBEAR="$INITRAMFS/sbin/dropbear"
if [ ! -f "$DROPBEAR" ]; then
    echo "Building static dropbear..."
    DROPBEAR_VER="2024.86"
    DROPBEAR_SRC="/tmp/dropbear-${DROPBEAR_VER}"

    if [ ! -d "$DROPBEAR_SRC" ]; then
        wget -q -O /tmp/dropbear.tar.bz2 \
            "https://matt.ucc.asn.au/dropbear/releases/dropbear-${DROPBEAR_VER}.tar.bz2"
        tar -xjf /tmp/dropbear.tar.bz2 -C /tmp
    fi

    cd "$DROPBEAR_SRC"
    ./configure \
        --host=aarch64-linux-gnu \
        --disable-zlib \
        --disable-pam \
        --disable-syslog \
        --disable-lastlog \
        --disable-utmp \
        --disable-utmpx \
        --disable-wtmp \
        --disable-wtmpx \
        --enable-static \
        LDFLAGS="-static" \
        CFLAGS="-Os" \
        > /dev/null 2>&1

    make -j"$(nproc)" PROGRAMS="dropbear dropbearkey scp" STATIC=1 \
        > /dev/null 2>&1

    cp dropbear "$INITRAMFS/sbin/dropbear"
    cp dropbearkey "$INITRAMFS/sbin/dropbearkey"
    cp scp "$INITRAMFS/bin/scp"
    chmod 755 "$INITRAMFS/sbin/dropbear" "$INITRAMFS/sbin/dropbearkey" "$INITRAMFS/bin/scp"
    echo "dropbear installed: $(ls -lh "$INITRAMFS/sbin/dropbear" | awk '{print $5}')"

    cd "$TOPDIR"
    rm -rf "$DROPBEAR_SRC" /tmp/dropbear.tar.bz2
else
    echo "dropbear already present"
fi

# --- Create busybox applet symlinks ---
echo "Installing busybox symlinks..."
for applet in $("$INITRAMFS/bin/busybox" --list 2>/dev/null || true); do
    case "$applet" in
        # sbin applets
        init|getty|syslogd|klogd|ifconfig|ip|route|udhcpc|reboot|halt|poweroff|hwclock|mdev|modprobe|insmod|rmmod|lsmod|switch_root|pivot_root|losetup|fdisk|mkswap|swapon|swapoff|mount|umount)
            ln -sf ../bin/busybox "$INITRAMFS/sbin/$applet"
            ;;
        # skip busybox itself
        busybox)
            ;;
        # everything else goes in /bin
        *)
            ln -sf busybox "$INITRAMFS/bin/$applet"
            ;;
    esac
done

# /init for kernel to find
ln -sf bin/busybox "$INITRAMFS/init"
ln -sf ../bin/busybox "$INITRAMFS/sbin/init"

# --- Set permissions ---
chmod 755 "$INITRAMFS/etc/init.d/rcS"
chmod 755 "$INITRAMFS/etc/init.d"/S[0-9][0-9]-*
chmod 755 "$INITRAMFS/etc/udhcpc.script"
chmod 600 "$INITRAMFS/etc/shadow"

# --- Pack initramfs ---
echo "Packing initramfs..."
cd "$INITRAMFS"
find . | cpio -H newc -o --quiet | gzip -9 > "$OUT"

echo "initramfs.cpio.gz: $(ls -lh "$OUT" | awk '{print $5}')"
echo "Done."
