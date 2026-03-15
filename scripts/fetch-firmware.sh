#!/bin/sh
set -e

FIRMWARE_DIR="$(cd "$(dirname "$0")/../firmware" && pwd)"
REPO="https://raw.githubusercontent.com/raspberrypi/firmware/master/boot"

FILES="
bootcode.bin
start.elf
start4.elf
fixup.dat
fixup4.dat
"

mkdir -p "$FIRMWARE_DIR"

for f in $FILES; do
    if [ -f "$FIRMWARE_DIR/$f" ]; then
        echo "Already have $f, skipping"
    else
        echo "Fetching $f ..."
        wget -q -O "$FIRMWARE_DIR/$f" "$REPO/$f"
    fi
done

echo "Firmware blobs in $FIRMWARE_DIR:"
ls -lh "$FIRMWARE_DIR"
