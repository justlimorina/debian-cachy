#!/usr/bin/env bash
set -e

BRANCH="${1:-6.13/master}"
LOCALVER="${2:--cachyos}"

echo "=========================================="
echo " Building CachyOS Kernel for Debian"
echo " Branch: $BRANCH"
echo " Suffix: $LOCALVER"
echo "=========================================="

# 1. Clone source code
echo "[1/4] Cloning CachyOS Linux source repository..."
git clone --depth 1 -b "$BRANCH" https://github.com/CachyOS/linux-cachyos.git kernel-src
cd kernel-src

# 2. Configure kernel
echo "[2/4] Setting up kernel configuration..."
if [ -f "../config/custom.config" ]; then
    echo "Using custom config from config/custom.config..."
    cp ../config/custom.config .config
    make olddefconfig
else
    echo "Generating defconfig with GitHub Actions optimizations..."
    make defconfig

    # Disable heavy debug info to save build time & disk space on CI
    ./scripts/config --disable CONFIG_DEBUG_INFO
    ./scripts/config --disable CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
    ./scripts/config --disable CONFIG_DEBUG_INFO_DWARF4
    ./scripts/config --disable CONFIG_DEBUG_INFO_DWARF5
    ./scripts/config --enable CONFIG_DEBUG_INFO_NONE
    ./scripts/config --disable CONFIG_DEBUG_INFO_BTF

    make olddefconfig
fi

# 3. Build .deb packages
echo "[3/4] Compiling kernel and packaging .deb files..."
make -j$(nproc) bindeb-pkg LOCALVERSION="$LOCALVER"

# 4. Move generated deb packages to workspace root
echo "[4/4] Moving generated .deb files..."
cd ..
mv *.deb ./ 2>/dev/null || true

echo "=========================================="
echo " Build Completed Successfully!"
echo "=========================================="
ls -lh *.deb
