#!/bin/sh
set -e

TOPDIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$TOPDIR/overlay"
ALPINE_VER="v3.21"
ALPINE_ARCH="aarch64"
ALPINE_REPOS="main community"
CACHE_DIR="$TOPDIR/.apk-cache"

usage() {
    echo "Usage: $0 <package-name> [package-name ...]"
    echo ""
    echo "Downloads Alpine Linux packages and extracts them into the overlay."
    echo "Includes musl dynamic linker automatically."
    echo ""
    echo "Run inside the build container:"
    echo "  podman run --rm -v \"\$(pwd)\":/build minpi-build /build/scripts/add-overlay-package.sh python3"
    echo ""
    echo "Then rebuild the image:"
    echo "  podman run --rm -v \"\$(pwd)\":/build minpi-build /build/scripts/build-image.sh"
    exit 1
}

[ $# -eq 0 ] && usage

mkdir -p "$CACHE_DIR"

# Fetch package index if not cached
fetch_index() {
    local repo="$1"
    local idx="$CACHE_DIR/APKINDEX-${repo}"
    if [ ! -f "$idx" ]; then
        echo "Fetching $repo package index..." >&2
        wget -q -O "$CACHE_DIR/idx-${repo}.tar.gz" \
            "https://dl-cdn.alpinelinux.org/alpine/${ALPINE_VER}/${repo}/${ALPINE_ARCH}/APKINDEX.tar.gz"
        tar -xzf "$CACHE_DIR/idx-${repo}.tar.gz" -C "$CACHE_DIR"
        mv "$CACHE_DIR/APKINDEX" "$idx"
        rm -f "$CACHE_DIR/idx-${repo}.tar.gz"
    fi
}

# Look up package version from index
find_pkg() {
    local pkg="$1"
    local repo ver
    for repo in $ALPINE_REPOS; do
        fetch_index "$repo"
        ver=$(awk -v pkg="$pkg" '
            /^P:/{name=substr($0,3)}
            /^V:/{ver=substr($0,3)}
            /^$/{if(name==pkg){print ver; exit}}
        ' "$CACHE_DIR/APKINDEX-${repo}")
        if [ -n "$ver" ]; then
            echo "$repo $ver"
            return 0
        fi
    done
    return 1
}

# Look up package dependencies
find_deps() {
    local pkg="$1"
    local repo
    for repo in $ALPINE_REPOS; do
        fetch_index "$repo"
        local result=$(awk -v pkg="$pkg" '
            /^P:/{name=substr($0,3)}
            /^D:/{deps=substr($0,3)}
            /^$/{if(name==pkg && deps!=""){print deps; exit}; deps=""}
        ' "$CACHE_DIR/APKINDEX-${repo}")
        if [ -n "$result" ]; then
            echo "$result"
            return
        fi
    done
}

# Download and extract a single package
install_pkg() {
    local pkg="$1"
    local info
    info=$(find_pkg "$pkg") || {
        echo "  WARNING: package '$pkg' not found, skipping"
        return 1
    }
    local repo=$(echo "$info" | head -1 | awk '{print $1}')
    local ver=$(echo "$info" | head -1 | awk '{print $2}')
    local url="https://dl-cdn.alpinelinux.org/alpine/${ALPINE_VER}/${repo}/${ALPINE_ARCH}/${pkg}-${ver}.apk"
    local apk="$CACHE_DIR/${pkg}-${ver}.apk"

    if [ -f "$CACHE_DIR/.installed-${pkg}" ]; then
        return 0
    fi

    echo "  Installing $pkg ($ver) from $repo..."

    # Download
    if [ ! -f "$apk" ]; then
        wget -q -O "$apk" "$url" || {
            echo "  WARNING: download failed for $pkg"
            rm -f "$apk"
            return 1
        }
    fi

    # Extract into initramfs (skip .PKGINFO and .SIGN files)
    tar -xzf "$apk" -C "$TARGET" --exclude='.PKGINFO' --exclude='.SIGN*' --exclude='.pre-*' --exclude='.post-*' --exclude='.trigger' 2>/dev/null || true

    touch "$CACHE_DIR/.installed-${pkg}"
    return 0
}

# Find which package provides a shared library
find_provider() {
    local soname="$1"
    local repo
    for repo in $ALPINE_REPOS; do
        fetch_index "$repo"
        local result=$(awk -v so="$soname" '
            /^P:/{name=substr($0,3)}
            /^p:/{provides=substr($0,3)}
            /^$/{
                if (provides ~ so) { print name; exit }
                provides=""
            }
        ' "$CACHE_DIR/APKINDEX-${repo}")
        if [ -n "$result" ]; then
            echo "$result"
            return
        fi
    done
}

# Resolve and install dependencies (recursive, handles so: deps)
install_with_deps() {
    local pkg="$1"
    local deps dep depname provider

    # Install dependencies first
    deps=$(find_deps "$pkg")
    for dep in $deps; do
        case "$dep" in
            so:*)
                # Shared library — find the package that provides it
                provider=$(find_provider "$dep")
                if [ -n "$provider" ]; then
                    install_with_deps "$provider"
                fi
                ;;
            pc:*|cmd:*)
                continue
                ;;
            *)
                # Strip version constraints
                depname=$(echo "$dep" | sed 's/[><=!].*//' | sed 's/~.*//')
                install_with_deps "$depname"
                ;;
        esac
    done

    # Install the package itself
    install_pkg "$pkg"
}

echo "=== Adding Alpine packages to overlay ==="

for pkg in "$@"; do
    echo "Processing $pkg..."
    install_with_deps "$pkg"
done

echo ""
echo "Done. Rebuild with:"
echo "  /build/scripts/build-image.sh"
