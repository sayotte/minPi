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

# Enable loadable modules
"$KERNEL_SRC/scripts/config" --file "$KERNEL_OUT/.config" --enable MODULES

# Clear built-in cmdline — we use cmdline.txt exclusively
"$KERNEL_SRC/scripts/config" --file "$KERNEL_OUT/.config" \
    --set-str CMDLINE ""

CFG="$KERNEL_SRC/scripts/config --file $KERNEL_OUT/.config"

# --- Tier 1: Zero-risk removals (no hardware present) ---
$CFG --disable MEDIA_SUPPORT          # DVB, V4L2, cameras, IR blasters
$CFG --disable INPUT_TOUCHSCREEN      # Touchscreens
# W1 left enabled — DS18B20 temperature sensors are common
$CFG --disable CAN                    # CAN bus
$CFG --disable MTD                    # Raw flash / NOR / NAND
$CFG --disable RC_CORE                # IR remote receivers
$CFG --disable RTC_CLASS              # Battery-backed real-time clocks
# NLS left enabled — needed for FAT filesystem support

# --- Tier 2: No-risk removals (features explicitly unwanted) ---
$CFG --disable BT                     # Bluetooth
$CFG --disable DM_CRYPT               # Device mapper / LVM
$CFG --disable DM_MIRROR
$CFG --disable DM_SNAPSHOT
$CFG --disable DM_THIN_PROVISIONING
$CFG --disable MD                     # Software RAID
$CFG --disable HWMON                  # Hardware monitoring sensors
$CFG --disable NETFILTER              # Firewall (also fixes case-collision build errors)
$CFG --disable IPV6                   # IPv6
$CFG --disable BRIDGE                 # Network bridging
$CFG --disable NET_SCHED              # Traffic shaping / QoS
$CFG --disable HAMRADIO               # Amateur radio
$CFG --disable CAIF                   # ST-Ericsson CAIF
$CFG --disable NFC                    # Near-field communication
$CFG --disable PCCARD                 # PCMCIA

# --- Tier 3: Unnecessary filesystems ---
$CFG --disable EXT2_FS
$CFG --disable EXT3_FS
$CFG --disable EXT4_FS
$CFG --disable BTRFS_FS
$CFG --disable XFS_FS
$CFG --disable F2FS_FS
$CFG --disable NTFS_FS
$CFG --disable NFS_FS
$CFG --disable NFSD
$CFG --disable CIFS
$CFG --disable ISO9660_FS
$CFG --disable UDF_FS
# VFAT_FS left enabled — boot partition, USB drives
$CFG --disable SQUASHFS
$CFG --disable FUSE_FS
$CFG --disable OVERLAY_FS
$CFG --disable AUTOFS_FS

# --- Tier 4: Unnecessary subsystems ---
$CFG --disable IIO                    # Industrial I/O (ADCs, IMUs, etc.)
$CFG --disable STAGING                # Staging drivers (RPi camera, etc.)
$CFG --disable ACCESSIBILITY          # Console accessibility
$CFG --disable ANDROID                # Android binder
# SCSI left enabled — needed by USB mass storage
$CFG --disable ATA                    # SATA
$CFG --disable POWER_SUPPLY           # Battery / charger drivers
# CONFIG_REGULATOR left enabled — WiFi power sequencing needs it
$CFG --disable MFD_CORE               # Multi-function device drivers

# --- Re-enabled for common headless peripherals ---
$CFG --enable I2C_CHARDEV             # /dev/i2c-* userspace access
$CFG --enable SPI_SPIDEV              # /dev/spidev* userspace access
$CFG --enable VFAT_FS                 # FAT32 filesystem (mount boot partition, USB drives)
$CFG --enable FAT_FS
$CFG --enable NLS_CODEPAGE_437        # Needed by FAT
$CFG --enable NLS_ISO8859_1           # Needed by FAT
$CFG --enable NLS_UTF8

# --- Tier 5: Virtual network interfaces and tunnels ---
$CFG --disable BONDING                # NIC bonding
$CFG --disable DUMMY                  # Dummy network device
$CFG --disable NET_IPGRE              # GRE tunnels
$CFG --disable NET_IPGRE_DEMUX        # GRE demux
$CFG --disable NET_IPIP               # IP-in-IP tunnels
$CFG --disable IP_VTI                 # IP VTI tunnels
$CFG --disable NET_IPVTI              # VTI interface
$CFG --disable NET_IP_TUNNEL          # IP tunnel core
$CFG --disable NET_UDP_TUNNEL         # UDP tunnel core
$CFG --disable INET_TUNNEL            # INET tunnel
$CFG --disable INET_XFRM_TUNNEL      # XFRM tunnel
$CFG --disable USB_HSO                # 3G/HSDPA USB modems
$CFG --disable TUN                    # TUN/TAP
$CFG --disable VETH                   # Virtual ethernet pairs
$CFG --disable MACVLAN                # MAC-based VLANs
$CFG --disable VLAN_8021Q             # 802.1Q VLANs
$CFG --disable VXLAN                  # VXLAN tunnels
$CFG --disable GENEVE                 # GENEVE tunnels
$CFG --disable L2TP                   # L2TP tunnels
$CFG --disable BATMAN_ADV             # Batman mesh networking
$CFG --disable WIREGUARD              # WireGuard VPN
$CFG --disable IEEE802154             # Zigbee / 802.15.4
$CFG --disable 6LOWPAN                # IPv6 over low-power wireless
$CFG --disable PPP                    # Point-to-point protocol
$CFG --disable SLIP                   # Serial line IP
$CFG --disable NET_SB1000             # SB1000 cable modem
$CFG --disable ATM                    # ATM networking
$CFG --disable DECNET                 # DECnet
$CFG --disable TIPC                   # TIPC cluster protocol
$CFG --disable PHONET                 # Nokia Phonet
$CFG --disable LAPB                   # LAPB (X.25)
$CFG --disable X25                    # X.25
$CFG --disable ATALK                  # AppleTalk
$CFG --disable XFRM_USER              # IPsec transform
$CFG --disable MAC80211_HWSIM         # WiFi hardware simulator (creates fake wlan1, hwsim0)

# --- Tier 5b: Excess WLAN drivers (keep only brcmfmac) ---
$CFG --disable WLAN_VENDOR_ADMTEK
$CFG --disable WLAN_VENDOR_ATH
$CFG --disable WLAN_VENDOR_ATMEL
$CFG --disable WLAN_VENDOR_CISCO
$CFG --disable WLAN_VENDOR_INTEL
$CFG --disable WLAN_VENDOR_INTERSIL
$CFG --disable WLAN_VENDOR_MARVELL
$CFG --disable WLAN_VENDOR_MEDIATEK
$CFG --disable WLAN_VENDOR_MICROCHIP
$CFG --disable WLAN_VENDOR_PURELIFI
$CFG --disable WLAN_VENDOR_RALINK
$CFG --disable WLAN_VENDOR_REALTEK
$CFG --disable WLAN_VENDOR_RSI
$CFG --disable WLAN_VENDOR_SILABS
$CFG --disable WLAN_VENDOR_ST
$CFG --disable WLAN_VENDOR_TI
$CFG --disable WLAN_VENDOR_ZYDAS
$CFG --disable WLAN_VENDOR_QUANTENNA
$CFG --disable B43                    # Old Broadcom driver (not brcmfmac)
$CFG --disable B43LEGACY
$CFG --disable BRCMSMAC               # Broadcom softmac (not what Pi uses)

# --- Tier 5c: Excess SND drivers (keep only core + SoC for VC4 dep) ---
$CFG --disable SND_USB                # USB audio
$CFG --disable SND_HDA                # HDA audio
$CFG --disable SND_PCI                # PCI audio
$CFG --disable SND_RAWMIDI
$CFG --disable SND_SEQUENCER
$CFG --disable SND_OSSEMUL            # OSS emulation
$CFG --disable SND_ALOOP              # Loopback
$CFG --disable SND_DUMMY              # Dummy sound
$CFG --disable SND_VIRMIDI            # Virtual MIDI
$CFG --disable SND_MTPAV
$CFG --disable SND_SERIAL_U16550
$CFG --disable SND_MPU401
# Disable all SoC codecs/platforms except BCM2835
$CFG --disable SND_SOC_INTEL_SST_TOPLEVEL
$CFG --disable SND_SOC_AMD_ACP_COMMON
$CFG --disable SND_SOC_SOF_TOPLEVEL
$CFG --disable SND_SOC_IMG
$CFG --disable SND_SIMPLE_CARD

# --- Tier 5d: Excess CRYPTO (keep core + algos needed for SSH/TLS) ---
$CFG --disable CRYPTO_USER
$CFG --disable CRYPTO_PCBC
$CFG --disable CRYPTO_XCBC
$CFG --disable CRYPTO_VMAC
$CFG --disable CRYPTO_CRC32C_GENERIC
$CFG --disable CRYPTO_XXHASH
$CFG --disable CRYPTO_MICHAEL_MIC
$CFG --disable CRYPTO_RMD160
$CFG --disable CRYPTO_TGR192
$CFG --disable CRYPTO_WP512
$CFG --disable CRYPTO_ANUBIS
$CFG --disable CRYPTO_ARC4
$CFG --disable CRYPTO_BLOWFISH
$CFG --disable CRYPTO_CAMELLIA
$CFG --disable CRYPTO_CAST5
$CFG --disable CRYPTO_CAST6
$CFG --disable CRYPTO_FCRYPT
$CFG --disable CRYPTO_KHAZAD
$CFG --disable CRYPTO_SEED
$CFG --disable CRYPTO_SERPENT
$CFG --disable CRYPTO_TEA
$CFG --disable CRYPTO_TWOFISH
$CFG --disable CRYPTO_842
$CFG --disable CRYPTO_LZ4
$CFG --disable CRYPTO_LZ4HC
$CFG --disable CRYPTO_ZSTD
$CFG --disable CRYPTO_USER_API_HASH
$CFG --disable CRYPTO_USER_API_SKCIPHER
$CFG --disable CRYPTO_USER_API_RNG
$CFG --disable CRYPTO_USER_API_AEAD
$CFG --disable CRYPTO_STATS
$CFG --disable CRYPTO_TEST

# --- Tier 5e: Excess serial, input, LEDs, I2C drivers ---
$CFG --disable SERIAL_8250_MANY_PORTS # Extra 8250 port support
$CFG --disable SERIAL_8250_EXAR
$CFG --disable SERIAL_8250_PCI
$CFG --disable INPUT_JOYDEV           # Joysticks
$CFG --disable INPUT_JOYSTICK
$CFG --disable INPUT_TABLET           # Tablets
$CFG --disable INPUT_MOUSEDEV         # Mouse (keep keyboard)
$CFG --disable INPUT_MOUSE
$CFG --disable LEDS_TRIGGER_TIMER
$CFG --disable LEDS_TRIGGER_ONESHOT
$CFG --disable LEDS_TRIGGER_HEARTBEAT
$CFG --disable LEDS_TRIGGER_BACKLIGHT
$CFG --disable LEDS_TRIGGER_CPU
$CFG --disable LEDS_TRIGGER_ACTIVITY
$CFG --disable LEDS_TRIGGER_PANIC
$CFG --disable LEDS_TRIGGER_TRANSIENT
$CFG --disable LEDS_TRIGGER_CAMERA
$CFG --disable LEDS_TRIGGER_NETDEV
$CFG --disable LEDS_TRIGGER_PATTERN
$CFG --disable LEDS_TRIGGER_AUDIO

# --- Tier 5f: Misc ---
$CFG --disable BCMA                   # Broadcom SSB bus (for B43, not brcmfmac)
$CFG --disable SSB                    # Silicon Sonics Backplane
$CFG --disable LOGO                   # Boot logo (raspberry at top of screen)
$CFG --disable DEBUG_FS               # debugfs
$CFG --disable PROFILING              # profiling support
$CFG --disable FTRACE                 # function tracer
$CFG --disable KPROBES                # kprobes
$CFG --disable PERF_EVENTS            # perf
$CFG --disable DEBUG_KERNEL           # debug kernel features
$CFG --disable CGROUP_BPF
$CFG --disable BPF_SYSCALL            # eBPF
$CFG --disable CGROUPS                # cgroups
$CFG --disable NAMESPACES             # namespaces (containers)
$CFG --disable SWAP                   # swap

# --- Tier 5g: Remaining SND HAT drivers (keep only core SoC for VC4) ---
$CFG --disable SND_BCM2708_SOC_CHIPDIP_DAC
$CFG --disable SND_BCM2708_SOC_GOOGLEVOICEHAT_SOUNDCARD
$CFG --disable SND_BCM2708_SOC_HIFIBERRY_ADC
$CFG --disable SND_BCM2708_SOC_HIFIBERRY_DAC
$CFG --disable SND_BCM2708_SOC_HIFIBERRY_DACPLUS
$CFG --disable SND_BCM2708_SOC_HIFIBERRY_DACPLUSHD
$CFG --disable SND_BCM2708_SOC_HIFIBERRY_DACPLUSADC
$CFG --disable SND_BCM2708_SOC_HIFIBERRY_DACPLUSADCPRO
$CFG --disable SND_BCM2708_SOC_HIFIBERRY_DIGI
$CFG --disable SND_BCM2708_SOC_HIFIBERRY_AMP
$CFG --disable SND_BCM2708_SOC_IQAUDIO_CODEC
$CFG --disable SND_BCM2708_SOC_IQAUDIO_DAC
$CFG --disable SND_BCM2708_SOC_IQAUDIO_DIGI
$CFG --disable SND_BCM2708_SOC_I_SABRE_Q2M
$CFG --disable SND_BCM2708_SOC_JUSTBOOM_BOTH
$CFG --disable SND_BCM2708_SOC_JUSTBOOM_DAC
$CFG --disable SND_BCM2708_SOC_JUSTBOOM_DIGI
$CFG --disable SND_BCM2708_SOC_PIFI_40
$CFG --disable SND_BCM2708_SOC_PIFI_DAC_HD
$CFG --disable SND_BCM2708_SOC_RPI_CIRRUS
$CFG --disable SND_BCM2708_SOC_RPI_DAC
$CFG --disable SND_BCM2708_SOC_RPI_PROTO
$CFG --disable SND_BCM2708_SOC_FE_PI_AUDIO
$CFG --disable SND_BCM2708_SOC_DIONAUDIO_LOCO
$CFG --disable SND_BCM2708_SOC_DIONAUDIO_LOCO_V2
$CFG --disable SND_BCM2708_SOC_ALLO_PIANO_DAC
$CFG --disable SND_BCM2708_SOC_ALLO_PIANO_DAC_PLUS
$CFG --disable SND_BCM2708_SOC_ALLO_BOSS_DAC
$CFG --disable SND_BCM2708_SOC_ALLO_BOSS2_DAC
$CFG --disable SND_BCM2708_SOC_ALLO_DIGIONE
$CFG --disable SND_BCM2708_SOC_ALLO_KATANA_DAC
$CFG --disable SND_PISOUND
$CFG --disable SND_SOC_WM5102
$CFG --disable SND_SOC_WM8804_I2C
$CFG --disable SND_SOC_WM8804_SPI
$CFG --disable SND_RAWMIDI
$CFG --disable SND_COMPRESS_OFFLOAD
$CFG --disable SND_SPI
$CFG --disable SND_DRIVERS

# --- Tier 5h: NLS codepages (keep 437, ISO-8859-1, UTF-8 for FAT) ---
$CFG --disable NLS_CODEPAGE_737
$CFG --disable NLS_CODEPAGE_775
$CFG --disable NLS_CODEPAGE_850
$CFG --disable NLS_CODEPAGE_852
$CFG --disable NLS_CODEPAGE_855
$CFG --disable NLS_CODEPAGE_857
$CFG --disable NLS_CODEPAGE_860
$CFG --disable NLS_CODEPAGE_861
$CFG --disable NLS_CODEPAGE_862
$CFG --disable NLS_CODEPAGE_863
$CFG --disable NLS_CODEPAGE_864
$CFG --disable NLS_CODEPAGE_865
$CFG --disable NLS_CODEPAGE_866
$CFG --disable NLS_CODEPAGE_869
$CFG --disable NLS_CODEPAGE_874
$CFG --disable NLS_CODEPAGE_932
$CFG --disable NLS_CODEPAGE_936
$CFG --disable NLS_CODEPAGE_949
$CFG --disable NLS_CODEPAGE_950
$CFG --disable NLS_CODEPAGE_1250
$CFG --disable NLS_CODEPAGE_1251
$CFG --disable NLS_ISO8859_2
$CFG --disable NLS_ISO8859_3
$CFG --disable NLS_ISO8859_4
$CFG --disable NLS_ISO8859_5
$CFG --disable NLS_ISO8859_6
$CFG --disable NLS_ISO8859_7
$CFG --disable NLS_ISO8859_8
$CFG --disable NLS_ISO8859_9
$CFG --disable NLS_ISO8859_13
$CFG --disable NLS_ISO8859_14
$CFG --disable NLS_ISO8859_15
$CFG --disable NLS_KOI8_R
$CFG --disable NLS_KOI8_U
$CFG --disable NLS_MAC_ROMAN
$CFG --disable NLS_MAC_CELTIC
$CFG --disable NLS_MAC_CENTEURO
$CFG --disable NLS_MAC_CROATIAN
$CFG --disable NLS_MAC_CYRILLIC
$CFG --disable NLS_MAC_GAELIC
$CFG --disable NLS_MAC_GREEK
$CFG --disable NLS_MAC_ICELAND
$CFG --disable NLS_MAC_INUIT
$CFG --disable NLS_MAC_ROMANIAN
$CFG --disable NLS_MAC_TURKISH

# --- Tier 5i: Remaining HID vendor drivers ---
$CFG --disable HID_ACRUX
$CFG --disable HID_ASUS
$CFG --disable HID_BETOP_FF
$CFG --disable HID_BIGBEN_FF
$CFG --disable HID_DRAGONRISE
$CFG --disable HID_EMS_FF
$CFG --disable HID_ELECOM
$CFG --disable HID_ELO
$CFG --disable HID_GEMBIRD
$CFG --disable HID_HOLTEK
$CFG --disable HID_KEYTOUCH
$CFG --disable HID_KYE
$CFG --disable HID_UCLOGIC
$CFG --disable HID_WALTOP
$CFG --disable HID_GYRATION
$CFG --disable HID_TWINHAN
$CFG --disable HID_LCPOWER
$CFG --disable HID_LED
$CFG --disable HID_LENOVO
$CFG --disable HID_MAGICMOUSE
$CFG --disable HID_MALTRON
$CFG --disable HID_MAYFLASH
$CFG --disable HID_NTI
$CFG --disable HID_NTRIG
$CFG --disable HID_ORTEK
$CFG --disable HID_PANTHERLORD
$CFG --disable HID_PETALYNX
$CFG --disable HID_PICOLCD
$CFG --disable HID_PRIMAX
$CFG --disable HID_REDRAGON
$CFG --disable HID_RETRODE
$CFG --disable HID_ROCCAT
$CFG --disable HID_SAITEK
$CFG --disable HID_SAMSUNG
$CFG --disable HID_SPEEDLINK
$CFG --disable HID_STEAM
$CFG --disable HID_STEELSERIES
$CFG --disable HID_THRUSTMASTER
$CFG --disable HID_VIEWSONIC
$CFG --disable HID_VIVALDI
$CFG --disable HID_WIIMOTE
$CFG --disable HID_XINMO
$CFG --disable HID_ZEROPLUS
$CFG --disable HID_ZYDACRON
$CFG --disable HID_SENSOR_HUB
$CFG --disable HID_ALPS
$CFG --disable HID_MCP2221
$CFG --disable HID_BATTERY_STRENGTH

# --- Tier 5j: Excess USB ethernet (keep only SMSC95XX + LAN78XX) ---
$CFG --disable USB_CATC
$CFG --disable USB_KAWETH
$CFG --disable USB_PEGASUS
$CFG --disable USB_RTL8150
$CFG --disable USB_RTL8152
$CFG --disable USB_NET_AX8817X
$CFG --disable USB_NET_AX88179_178A
$CFG --disable USB_NET_CDCETHER
$CFG --disable USB_NET_CDC_EEM
$CFG --disable USB_NET_CDC_NCM
$CFG --disable USB_NET_HUAWEI_CDC_NCM
$CFG --disable USB_NET_CDC_MBIM
$CFG --disable USB_NET_DM9601
$CFG --disable USB_NET_SR9700
$CFG --disable USB_NET_SR9800
$CFG --disable USB_NET_SMSC75XX
$CFG --disable USB_NET_GL620A
$CFG --disable USB_NET_NET1080
$CFG --disable USB_NET_MCS7830
$CFG --disable USB_NET_PLUSB
$CFG --disable USB_NET_RNDIS_HOST
$CFG --disable USB_NET_CDC_SUBSET
$CFG --disable USB_NET_ZAURUS
$CFG --disable USB_NET_CX82310_ETH
$CFG --disable USB_NET_KALMIA
$CFG --disable USB_NET_QMI_WWAN
$CFG --disable USB_NET_INT51X1
$CFG --disable USB_IPHETH
$CFG --disable USB_NET_CH9200
$CFG --disable USB_NET_AQC111

# --- Tier 6: Excess USB drivers (keep DWC2 + USB-net + serial + storage) ---
# USB_SERIAL and USB_STORAGE left enabled — common headless peripherals
$CFG --disable USB_GADGET             # USB gadget/device mode
$CFG --disable USB_XHCI_HCD          # xHCI (USB 3.0 host)
$CFG --disable USB_EHCI_HCD          # EHCI (USB 2.0 host — DWC2 has its own)
$CFG --disable USB_OHCI_HCD          # OHCI
$CFG --disable USB_ACM                # USB modems
$CFG --disable USB_WDM                # USB wireless modems
$CFG --disable USB_TMC                # USB test & measurement

# --- Tier 7: Excess HID drivers (keep generic + USB HID) ---
$CFG --disable HID_A4TECH
$CFG --disable HID_APPLE
$CFG --disable HID_BELKIN
$CFG --disable HID_CHERRY
$CFG --disable HID_CHICONY
$CFG --disable HID_CYPRESS
$CFG --disable HID_EZKEY
$CFG --disable HID_ITE
$CFG --disable HID_KENSINGTON
$CFG --disable HID_LOGITECH
$CFG --disable HID_MICROSOFT
$CFG --disable HID_MONTEREY
$CFG --disable HID_MULTITOUCH
$CFG --disable HID_PLANTRONICS
$CFG --disable HID_SONY
$CFG --disable HID_SUNPLUS

# Resolve dependencies
make -C "$KERNEL_SRC" O="$KERNEL_OUT" olddefconfig

# Save the resolved config back to the repo for reference
cp "$KERNEL_OUT/.config" "$TOPDIR/kernel/config"
echo "Resolved config saved to kernel/config"

# Build
echo "Building kernel with $NPROC jobs..."
make -C "$KERNEL_SRC" O="$KERNEL_OUT" -j"$NPROC" Image dtbs modules

# Install modules into initramfs
echo "Installing modules..."
make -C "$KERNEL_SRC" O="$KERNEL_OUT" \
    INSTALL_MOD_PATH="$TOPDIR/initramfs" \
    modules_install
# Remove build/source symlinks (they point to the build machine)
rm -f "$TOPDIR/initramfs/lib/modules"/*/build
rm -f "$TOPDIR/initramfs/lib/modules"/*/source

# Generate modules.dep
echo "Running depmod..."
KREL=$(cat "$KERNEL_OUT/include/config/kernel.release")
depmod -a -b "$TOPDIR/initramfs" "$KREL"

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
