FROM debian:bookworm-slim

RUN echo 'Acquire::Check-Date "false";' > /etc/apt/apt.conf.d/99no-check-date \
    && apt-get update && apt-get install -y --no-install-recommends \
    # Cross-compilation toolchain
    gcc-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu \
    # Kernel build dependencies
    make \
    flex \
    bison \
    bc \
    libssl-dev \
    libc6-dev \
    # Kernel source fetching
    git \
    ca-certificates \
    wget \
    # Dropbear / wpa_supplicant / iw build dependencies
    bzip2 \
    autoconf \
    pkg-config \
    libnl-3-dev \
    libnl-genl-3-dev \
    # Module tools (depmod)
    kmod \
    # initramfs packing
    cpio \
    gzip \
    xz-utils \
    # SD card image assembly
    dosfstools \
    mtools \
    fdisk \
    parted \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
