#!/usr/bin/env bash
set -e

# CachyOS/linux repo branch (contains fully patched kernel source)
CACHY_BRANCH="${1:-7.2}"
SCHEDULER="${2:-bore}"
LOCALVER="${3:--cachyos}"

echo "=========================================="
echo " Building CachyOS Kernel for Debian"
echo " CachyOS Branch: $CACHY_BRANCH"
echo " Scheduler:      $SCHEDULER"
echo " Suffix:         $LOCALVER"
echo "=========================================="

# 1. Clone CachyOS pre-patched kernel source
# CachyOS/linux repo contains the FULL kernel source with ALL patches already applied.
# Using shallow clone (--depth 1) to grab only the latest commit — fast and reliable.
echo "[1/4] Cloning CachyOS pre-patched kernel source (branch: $CACHY_BRANCH)..."
git clone --depth 1 -b "$CACHY_BRANCH" https://github.com/CachyOS/linux.git kernel-src

cd kernel-src

# 2. Configure kernel
echo "[2/4] Setting up kernel configuration..."
if [ -f "../../config/custom.config" ]; then
    echo "Using custom config from config/custom.config..."
    cp ../../config/custom.config .config
else
    # Start from kernel defconfig (guaranteed compatible with runner GCC)
    echo "Generating base defconfig..."
    make defconfig

    # Layer CachyOS performance features on top
    echo "Applying CachyOS performance options..."

    # --- CPU Scheduler: BORE ---
    ./scripts/config --enable CONFIG_SCHED_BORE 2>/dev/null || true

    # --- Network: BBRv3 ---
    ./scripts/config --enable CONFIG_TCP_CONG_BBR
    ./scripts/config --set-str CONFIG_DEFAULT_TCP_CONG "bbr"

    # --- CPU Performance ---
    ./scripts/config --enable CONFIG_X86_AMD_PSTATE 2>/dev/null || true
    ./scripts/config --enable CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL 2>/dev/null || true
    ./scripts/config --enable CONFIG_HZ_1000
    ./scripts/config --set-val CONFIG_HZ 1000
    ./scripts/config --enable CONFIG_PREEMPT
    ./scripts/config --enable CONFIG_PREEMPT_DYNAMIC 2>/dev/null || true
    ./scripts/config --enable CONFIG_NO_HZ_FULL

    # --- Memory Management ---
    ./scripts/config --enable CONFIG_LRU_GEN 2>/dev/null || true
    ./scripts/config --enable CONFIG_LRU_GEN_ENABLED 2>/dev/null || true
    ./scripts/config --enable CONFIG_ZSWAP
    ./scripts/config --enable CONFIG_ZSWAP_DEFAULT_ON 2>/dev/null || true
    ./scripts/config --enable CONFIG_ZRAM
    ./scripts/config --enable CONFIG_ZSMALLOC

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
fi

make olddefconfig

# 3. Build .deb packages
echo "[3/4] Compiling kernel and packaging .deb files..."
make -j$(nproc) bindeb-pkg LOCALVERSION="$LOCALVER" DPKG_FLAGS="-d"

# 4. Move generated deb packages to workspace root
echo "[4/4] Moving generated .deb files..."
cd ..
mv *.deb ../ 2>/dev/null || true

echo "=========================================="
echo " Build Completed Successfully!"
echo "=========================================="
cd ..
ls -lh *.deb
