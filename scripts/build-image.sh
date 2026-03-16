#!/bin/sh
set -e

TOPDIR="$(cd "$(dirname "$0")/.." && pwd)"
IMG="$TOPDIR/minpi.img"
IMG_SIZE_MB=128
PART_OFFSET_SECTORS=2048  # 1MiB offset (2048 * 512 = 1MiB)

echo "=== minPi image builder ==="

# Record commit hash
COMMIT="unknown"
if command -v git >/dev/null 2>&1 && [ -d "$TOPDIR/.git" ]; then
    COMMIT=$(git -C "$TOPDIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
fi
echo "$COMMIT" > "$TOPDIR/boot/commit.txt"
echo "Commit: $COMMIT"

# Verify all pieces exist
for f in \
    "$TOPDIR/firmware/bootcode.bin" \
    "$TOPDIR/firmware/start.elf" \
    "$TOPDIR/firmware/fixup.dat" \
    "$TOPDIR/kernel/kernel8.img" \
    "$TOPDIR/initramfs.cpio.gz" \
    "$TOPDIR/boot/config.txt" \
    "$TOPDIR/boot/cmdline.txt"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing $f"
        exit 1
    fi
done

# Create empty image
echo "Creating ${IMG_SIZE_MB}MB image..."
dd if=/dev/zero of="$IMG" bs=1M count="$IMG_SIZE_MB" status=none

# Partition table: single FAT32 partition starting at 1MiB
echo "Partitioning..."
parted -s "$IMG" \
    mklabel msdos \
    mkpart primary fat32 1MiB 100% \
    set 1 boot on \
    set 1 lba on

# Format the partition inside the image using mtools
PART_OFFSET_BYTES=$((PART_OFFSET_SECTORS * 512))
PART_SIZE_BYTES=$(( (IMG_SIZE_MB * 1048576) - PART_OFFSET_BYTES ))

# Extract the partition into a temp file, format it, put it back
PART_FILE="/tmp/minpi-part.img"
dd if="$IMG" of="$PART_FILE" bs=512 skip="$PART_OFFSET_SECTORS" status=none
mkfs.vfat -F 32 -n MINPI "$PART_FILE"

# Copy files using mcopy (mtools)
# MTOOLS_SKIP_CHECK avoids geometry warnings on image files
export MTOOLS_SKIP_CHECK=1

copy_file() {
    mcopy -i "$PART_FILE" "$1" "::$(basename "$1")"
    echo "  $(basename "$1") ($(ls -lh "$1" | awk '{print $5}'))"
}

echo "Copying files to image..."

# VideoCore firmware
copy_file "$TOPDIR/firmware/bootcode.bin"
copy_file "$TOPDIR/firmware/start.elf"
[ -f "$TOPDIR/firmware/start4.elf" ] && copy_file "$TOPDIR/firmware/start4.elf"
copy_file "$TOPDIR/firmware/fixup.dat"
[ -f "$TOPDIR/firmware/fixup4.dat" ] && copy_file "$TOPDIR/firmware/fixup4.dat"

# Boot config
copy_file "$TOPDIR/boot/config.txt"
copy_file "$TOPDIR/boot/cmdline.txt"
copy_file "$TOPDIR/boot/commit.txt"

# Kernel
copy_file "$TOPDIR/kernel/kernel8.img"

# DTBs (firmware auto-selects by board revision)
if [ -d "$TOPDIR/kernel/dtbs" ]; then
    for dtb in "$TOPDIR/kernel/dtbs"/*.dtb; do
        copy_file "$dtb"
    done
fi

# initramfs (8.3-safe filename to avoid FAT long name issues)
mcopy -i "$PART_FILE" "$TOPDIR/initramfs.cpio.gz" "::ramfs.gz"
echo "  ramfs.gz ($(ls -lh "$TOPDIR/initramfs.cpio.gz" | awk '{print $5}'))"

# Show contents
echo ""
echo "Boot partition contents:"
mdir -i "$PART_FILE" ::
echo ""

# Write the formatted partition back into the image
dd if="$PART_FILE" of="$IMG" bs=512 seek="$PART_OFFSET_SECTORS" conv=notrunc status=none
rm -f "$PART_FILE"

echo "Image: $IMG ($(ls -lh "$IMG" | awk '{print $5}'))"
echo "Done. Flash with: dd if=minpi.img of=/dev/sdX bs=4M status=progress"
