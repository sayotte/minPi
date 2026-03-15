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
    # Dropbear build dependencies
    bzip2 \
    autoconf \
    # initramfs packing
    cpio \
    gzip \
    # SD card image assembly
    dosfstools \
    mtools \
    fdisk \
    parted \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
