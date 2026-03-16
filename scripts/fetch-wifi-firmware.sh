#!/bin/sh
set -e

TOPDIR="$(cd "$(dirname "$0")/.." && pwd)"
FW_DIR="$TOPDIR/initramfs/lib/firmware/brcm"
CYPRESS="https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/bookworm/debian/config/brcm80211/cypress"
BRCM="https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/bookworm/debian/config/brcm80211/brcm"

mkdir -p "$FW_DIR"

fetch() {
    local url="$1"
    local dest="$2"
    if [ -f "$dest" ]; then
        echo "Already have $(basename "$dest")"
        return
    fi
    echo "Fetching $(basename "$dest") ..."
    if ! wget -q -O "$dest" "$url"; then
        echo "  WARNING: failed, skipping"
        rm -f "$dest"
    fi
}

# Pi 3B: BCM43430
fetch "$CYPRESS/cyfmac43430-sdio.bin"      "$FW_DIR/brcmfmac43430-sdio.bin"
fetch "$CYPRESS/cyfmac43430-sdio.clm_blob" "$FW_DIR/brcmfmac43430-sdio.clm_blob"
fetch "$BRCM/brcmfmac43430-sdio.txt"       "$FW_DIR/brcmfmac43430-sdio.txt"
# Board-specific NVRAM files are symlinks on GitHub; copy the generic one instead
cp "$FW_DIR/brcmfmac43430-sdio.txt" \
    "$FW_DIR/brcmfmac43430-sdio.raspberrypi,3-model-b.txt"

# Pi 3B+ / 3A+: BCM43455
fetch "$CYPRESS/cyfmac43455-sdio-standard.bin" "$FW_DIR/brcmfmac43455-sdio.bin"
fetch "$CYPRESS/cyfmac43455-sdio.clm_blob"     "$FW_DIR/brcmfmac43455-sdio.clm_blob"
fetch "$BRCM/brcmfmac43455-sdio.txt"           "$FW_DIR/brcmfmac43455-sdio.txt"
cp "$FW_DIR/brcmfmac43455-sdio.txt" \
    "$FW_DIR/brcmfmac43455-sdio.raspberrypi,3-model-b-plus.txt"
cp "$FW_DIR/brcmfmac43455-sdio.txt" \
    "$FW_DIR/brcmfmac43455-sdio.raspberrypi,3-model-a-plus.txt"

# Pi Zero 2 W: BCM43436s
fetch "$CYPRESS/cyfmac43436s-sdio.bin"      "$FW_DIR/brcmfmac43436s-sdio.bin"
fetch "$CYPRESS/cyfmac43436s-sdio.clm_blob" "$FW_DIR/brcmfmac43436s-sdio.clm_blob"
fetch "$BRCM/brcmfmac43436s-sdio.txt"       "$FW_DIR/brcmfmac43436s-sdio.txt"

# Regulatory database (extract from tarball)
REGDB_DIR="$TOPDIR/initramfs/lib/firmware"
if [ ! -f "$REGDB_DIR/regulatory.db" ]; then
    echo "Fetching regulatory.db..."
    REGDB_VER="2026.02.04"
    wget -q -O /tmp/regdb.tar.xz \
        "https://cdn.kernel.org/pub/software/network/wireless-regdb/wireless-regdb-${REGDB_VER}.tar.xz"
    tar -xJf /tmp/regdb.tar.xz -C /tmp \
        "wireless-regdb-${REGDB_VER}/regulatory.db" \
        "wireless-regdb-${REGDB_VER}/regulatory.db.p7s"
    cp "/tmp/wireless-regdb-${REGDB_VER}/regulatory.db" "$REGDB_DIR/"
    cp "/tmp/wireless-regdb-${REGDB_VER}/regulatory.db.p7s" "$REGDB_DIR/"
    rm -rf /tmp/regdb.tar.xz "/tmp/wireless-regdb-${REGDB_VER}"
else
    echo "Already have regulatory.db"
fi

# TX cap blobs (board-specific, from RPi-Distro — may not exist for all chips)
fetch "$CYPRESS/cyfmac43430-sdio.txcap_blob" "$FW_DIR/brcmfmac43430-sdio.txcap_blob"
fetch "$CYPRESS/cyfmac43455-sdio.txcap_blob" "$FW_DIR/brcmfmac43455-sdio.txcap_blob"

echo ""
echo "WiFi firmware in $FW_DIR:"
ls -lh "$FW_DIR"
