#!/usr/bin/env bash
set -e

KERNEL_VER="${1:-7.2.2}"
PATCH_VER="${2:-7.2}"
SCHEDULER="${3:-bore}"
LOCALVER="${4:--cachyos}"

echo "=========================================="
echo " Building CachyOS Kernel for Debian"
echo " Kernel Version: $KERNEL_VER"
echo " Patch Version:  $PATCH_VER"
echo " Scheduler:      $SCHEDULER"
echo " Suffix:         $LOCALVER"
echo "=========================================="

# 1. Download official Linux Kernel source
MAJOR_VER=$(echo "$KERNEL_VER" | cut -d. -f1)
TARBALL="linux-${KERNEL_VER}.tar.xz"
TARBALL_URL="https://cdn.kernel.org/pub/linux/kernel/v${MAJOR_VER}.x/${TARBALL}"

echo "[1/5] Downloading kernel source from $TARBALL_URL..."
curl -sSL "$TARBALL_URL" -o "$TARBALL"
mkdir -p kernel-src
tar -xJf "$TARBALL" -C kernel-src --strip-components=1
rm -f "$TARBALL"

cd kernel-src

# 2. Download CachyOS Patches
echo "[2/5] Fetching CachyOS patches..."
git clone --depth 1 https://github.com/CachyOS/kernel-patches.git ../patches

PATCH_DIR="../patches/${PATCH_VER}"
if [ -d "$PATCH_DIR" ]; then
    echo "Applying main CachyOS patches from $PATCH_DIR..."
    for p in "$PATCH_DIR"/*.patch; do
        if [ -f "$p" ]; then
            echo " -> Applying $(basename "$p")"
            patch -p1 -F3 -s < "$p" || echo "   (Warning: Some hunks skipped in $(basename "$p"))"
        fi
    done

    # Apply Scheduler patch
    if [ "$SCHEDULER" = "bore" ]; then
        if [ -f "$PATCH_DIR/sched/0001-bore-cachy.patch" ]; then
            echo " -> Applying BORE scheduler patch (0001-bore-cachy.patch)..."
            patch -p1 -F3 -s < "$PATCH_DIR/sched/0001-bore-cachy.patch" || true
        elif [ -f "$PATCH_DIR/sched/0001-bore.patch" ]; then
            echo " -> Applying BORE scheduler patch (0001-bore.patch)..."
            patch -p1 -F3 -s < "$PATCH_DIR/sched/0001-bore.patch" || true
        fi
    fi
else
    echo "Warning: Patch directory $PATCH_DIR not found. Proceeding with vanilla kernel."
fi

# 3. Configure kernel
echo "[3/5] Setting up kernel configuration..."
if [ -f "../../config/custom.config" ]; then
    echo "Using custom config from config/custom.config..."
    cp ../../config/custom.config .config
    make olddefconfig
else
    # Start from the kernel's own defconfig (guaranteed compatible with current GCC)
    # then layer CachyOS-specific performance features on top.
    echo "Generating base defconfig for this toolchain..."
    make defconfig

    echo "Applying CachyOS performance tweaks on top of defconfig..."

    # --- CPU Scheduler: BORE ---
    ./scripts/config --enable CONFIG_SCHED_BORE 2>/dev/null || true

    # --- Network: BBRv3 ---
    ./scripts/config --enable CONFIG_TCP_CONG_BBR
    ./scripts/config --set-str CONFIG_DEFAULT_TCP_CONG "bbr"

    # --- CPU Performance ---
    ./scripts/config --enable CONFIG_X86_AMD_PSTATE
    ./scripts/config --enable CONFIG_X86_AMD_PSTATE_DEFAULT_MODE 2>/dev/null || true
    ./scripts/config --enable CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL
    ./scripts/config --enable CONFIG_HZ_1000
    ./scripts/config --set-val CONFIG_HZ 1000
    ./scripts/config --enable CONFIG_PREEMPT
    ./scripts/config --enable CONFIG_PREEMPT_DYNAMIC 2>/dev/null || true
    ./scripts/config --enable CONFIG_NO_HZ_FULL

    # --- Memory Management ---
    ./scripts/config --enable CONFIG_LRU_GEN
    ./scripts/config --enable CONFIG_LRU_GEN_ENABLED
    ./scripts/config --enable CONFIG_ZSWAP
    ./scripts/config --enable CONFIG_ZSWAP_DEFAULT_ON
    ./scripts/config --enable CONFIG_ZRAM
    ./scripts/config --enable CONFIG_ZSMALLOC

    # --- I/O Scheduler ---
    ./scripts/config --enable CONFIG_MQ_IOSCHED_KYBER
    ./scripts/config --enable CONFIG_BLK_CGROUP

    # --- Futex / Wine / Gaming ---
    ./scripts/config --enable CONFIG_FUTEX
    ./scripts/config --enable CONFIG_FUTEX_PI

    # --- Disable features incompatible with GitHub Actions runner ---
    ./scripts/config --disable CONFIG_RUST
    ./scripts/config --disable CONFIG_DEBUG_INFO
    ./scripts/config --disable CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
    ./scripts/config --disable CONFIG_DEBUG_INFO_DWARF4
    ./scripts/config --disable CONFIG_DEBUG_INFO_DWARF5
    ./scripts/config --enable CONFIG_DEBUG_INFO_NONE
    ./scripts/config --disable CONFIG_DEBUG_INFO_BTF
    ./scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
    ./scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""

    make olddefconfig
fi

# 4. Build .deb packages
echo "[4/5] Compiling kernel and packaging .deb files..."
make -j$(nproc) bindeb-pkg LOCALVERSION="$LOCALVER" DPKG_FLAGS="-d"

# 5. Move generated deb packages to workspace root
echo "[5/5] Moving generated .deb files..."
cd ..
mv *.deb ../ 2>/dev/null || true

echo "=========================================="
echo " Build Completed Successfully!"
echo "=========================================="
cd ..
ls -lh *.deb
