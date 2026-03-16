#!/bin/sh
set -e

TOPDIR="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_SRC="${KERNEL_SRC:-/build/linux}"
KERNEL_OUT="${KERNEL_OUT:-/build/linux-out}"

usage() {
    echo "Usage: $0 <path-to-module-source>"
    echo ""
    echo "Builds an out-of-tree kernel module against the minPi kernel."
    echo "The module source directory must contain a Makefile."
    echo ""
    echo "Example:"
    echo "  podman run --rm \\"
    echo "    -v .:/build \\"
    echo "    -v minpi-linux-src:/build/linux \\"
    echo "    -v minpi-linux-out:/build/linux-out \\"
    echo "    minpi-build /build/scripts/build-module.sh /build/my-driver/"
    echo ""
    echo "The .ko file will be in the module source directory."
    echo "Copy it to initramfs/lib/modules/\$(uname -r)/extra/ and rebuild."
    exit 1
}

[ $# -eq 0 ] && usage
MODULE_SRC="$1"

if [ ! -f "$MODULE_SRC/Makefile" ]; then
    echo "ERROR: No Makefile found in $MODULE_SRC"
    exit 1
fi

if [ ! -f "$KERNEL_OUT/.config" ]; then
    echo "ERROR: Kernel not built yet. Run build-kernel.sh first."
    exit 1
fi

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

echo "Building module from $MODULE_SRC..."
make -C "$KERNEL_SRC" O="$KERNEL_OUT" M="$MODULE_SRC" modules

echo ""
echo "Built modules:"
find "$MODULE_SRC" -name '*.ko' -exec ls -lh {} \;
echo ""
echo "To include in the image, copy the .ko to:"
echo "  initramfs/lib/modules/\$(cat $KERNEL_OUT/include/config/kernel.release)/extra/"
echo "Then rebuild: build-initramfs.sh && build-image.sh"
