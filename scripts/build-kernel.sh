#!/bin/sh
set -e

TOPDIR="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_BRANCH="rpi-6.6.y"
KERNEL_REPO="https://github.com/raspberrypi/linux.git"
KERNEL_SRC="${KERNEL_SRC:-/build/linux}"
# Build output on case-sensitive filesystem (Linux volume, not macOS bind mount)
KERNEL_OUT="${KERNEL_OUT:-/build/linux-out}"
NPROC=$(nproc)

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# Clone kernel source (shallow) if not already present
if [ ! -d "$KERNEL_SRC/.git" ]; then
    echo "Cloning kernel source (shallow, branch $KERNEL_BRANCH)..."
    git clone --depth 1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_SRC"
else
    echo "Kernel source already present at $KERNEL_SRC"
fi

mkdir -p "$KERNEL_OUT"

# Use RPi Foundation's defconfig as the base
echo "Generating config from bcm2711_defconfig..."
make -C "$KERNEL_SRC" O="$KERNEL_OUT" bcm2711_defconfig

# Disable modules (everything built-in)
"$KERNEL_SRC/scripts/config" --file "$KERNEL_OUT/.config" --disable MODULES

# Clear built-in cmdline — we use cmdline.txt exclusively
"$KERNEL_SRC/scripts/config" --file "$KERNEL_OUT/.config" \
    --set-str CMDLINE ""

# Disable netfilter modules that collide on case-insensitive filesystems
# (xt_RATEEST.c vs xt_rateest.c, xt_DSCP.c vs xt_dscp.c, etc.)
for sym in NETFILTER_XT_TARGET_RATEEST NETFILTER_XT_TARGET_DSCP \
           NETFILTER_XT_TARGET_HL NETFILTER_XT_TARGET_TCPMSS; do
    "$KERNEL_SRC/scripts/config" --file "$KERNEL_OUT/.config" --disable "$sym"
done

# Resolve dependencies
make -C "$KERNEL_SRC" O="$KERNEL_OUT" olddefconfig

# Save the resolved config back to the repo for reference
cp "$KERNEL_OUT/.config" "$TOPDIR/kernel/config"
echo "Resolved config saved to kernel/config"

# Build
echo "Building kernel with $NPROC jobs..."
make -C "$KERNEL_SRC" O="$KERNEL_OUT" -j"$NPROC" Image dtbs

# Copy kernel image (raw, no appended DTB — firmware loads DTB separately)
IMAGE="$KERNEL_OUT/arch/arm64/boot/Image"
cp "$IMAGE" "$TOPDIR/kernel/kernel8.img"
ls -lh "$TOPDIR/kernel/kernel8.img"

# Copy DTBs — firmware auto-detects board and loads the right one
DTB_DIR="$KERNEL_OUT/arch/arm64/boot/dts/broadcom"
DTB_OUT="$TOPDIR/kernel/dtbs"
mkdir -p "$DTB_OUT"
for dtb in \
    bcm2710-rpi-zero-2-w.dtb \
    bcm2710-rpi-3-b.dtb \
    bcm2710-rpi-3-b-plus.dtb \
    bcm2837-rpi-3-a-plus.dtb; do
    if [ -f "$DTB_DIR/$dtb" ]; then
        cp "$DTB_DIR/$dtb" "$DTB_OUT/"
        echo "Copied $dtb"
    else
        echo "WARNING: $dtb not found"
    fi
done

echo "Done."
