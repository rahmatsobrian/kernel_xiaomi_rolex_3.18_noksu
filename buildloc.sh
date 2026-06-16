#!/bin/bash

# ================= COLOR =================
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
white='\033[0m'

# ================= PATH =================
DEFCONFIG=rolex_defconfig
ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"
KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG="$OUTDIR/Image.gz"

# ================= INFO =================
KERNEL_NAME="Yoru"
DEVICE="rolex"
export KBUILD_BUILD_USER="Hoshino"
export KBUILD_BUILD_HOST="Yoru"

# =============== DATE (WIB) ===============
DATE_TITLE=$(TZ=Asia/Jakarta date +"%d%m%Y")
TIME_TITLE=$(TZ=Asia/Jakarta date +"%H%M%S")
BUILD_DATETIME=$(TZ=Asia/Jakarta date +"%d %B %Y")

# ================= TOOLCHAIN =================
TC64="$ROOTDIR/linegcc49/bin/aarch64-linux-android-"
TC32="$ROOTDIR/linegcc49/bin/arm-linux-androideabi-"

# ================= GLOBAL =================
BUILD_TIME="unknown"
KERNEL_VERSION="unknown"
TC_INFO="unknown"
IMG_USED="unknown"
MD5_HASH="unknown"
ZIP_NAME=""

# ================= FUNCTION =================

setup_env() {
    echo -e "${yellow}[+] Setting up Local Environment...${white}"
    
    # Membuat folder log lokal
    mkdir -p logs

    # Instalasi dependencies (Butuh akses sudo)
    echo -e "${yellow}[+] Installing necessary packages...${white}"
    sudo apt-get update -y
    sudo apt-get install -y \
        dialog bash sed wget git curl zip tar jq expect make cmake automake autoconf \
        llvm lld lldb clang gcc binutils bison perl gperf gawk flex bc python3 zstd \
        openssl unzip cpio build-essential ccache liblz4-tool libsdl1.2-dev libstdc++6 \
        libxml2 libxml2-utils lzop pngcrush schedtool squashfs-tools xsltproc zlib1g-dev \
        libncurses5-dev bzip2 gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf \
        gcc-arm-linux-gnueabi dos2unix kmod

    # Setup Toolchain (GCC 4.9)
    if [ ! -d "$ROOTDIR/linegcc49" ]; then
        echo -e "${yellow}[+] Cloning GCC 4.9 Toolchain...${white}"
        git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git linegcc49
    else
        echo -e "${green}[✓] GCC 4.9 Toolchain already exists.${white}"
    fi

    # Setup KernelSU (Hookless - syscall)
    echo -e "${yellow}[+] Setting up KernelSU (Hookless)...${white}"
    curl -LSs "https://raw.githubusercontent.com/Mr-Morat/KernelSU-Next/stable/kernel/setup.sh" | bash -s syscall
}

clone_anykernel() {
    if [ ! -d "$ANYKERNEL_DIR" ]; then
        echo -e "${yellow}[+] Cloning AnyKernel3...${white}"
        git clone https://github.com/rahmatsobrian/AnyKernel3.git "$ANYKERNEL_DIR" || exit 1
    fi
}

get_toolchain_info() {
    if [ -x "${TC64}gcc" ]; then
        if ${TC64}gcc --version | grep -qi prerelease; then
            TC_INFO="GCC 4.9 Prerelease"
        else
            TC_INFO="GCC 4.9.x"
        fi
    else
        TC_INFO="unknown"
    fi
}

get_kernel_version() {
    if [ -f "Makefile" ]; then
        VERSION=$(grep -E '^VERSION =' Makefile | awk '{print $3}')
        PATCHLEVEL=$(grep -E '^PATCHLEVEL =' Makefile | awk '{print $3}')
        SUBLEVEL=$(grep -E '^SUBLEVEL =' Makefile | awk '{print $3}')
        KERNEL_VERSION="${VERSION}.${PATCHLEVEL}.${SUBLEVEL}"
    else
        KERNEL_VERSION="unknown"
    fi
}

# ================= Build Kernel =================
build_kernel() {
    echo -e "${yellow}[+] Getting toolchain info...${white}"
    get_toolchain_info
    
    echo -e "${yellow}[+] Removing out folder...${white}"
    rm -rf out
    
    echo -e "${yellow}[+] Creating out folder...${white}"
    mkdir -p out

    # Setting config
    echo -e "${yellow}[+] Preparing kernel config...${white}"
    make O=out ARCH=arm64 ${DEFCONFIG} || {
        echo -e "${red}[!] Make defconfig failed!${white}"
        exit 1
    }

    BUILD_START=$(TZ=Asia/Jakarta date +%s)

    echo -e "${yellow}[+] Building Kernel...${white}"
    # Memasukkan output ke log lokal dan terminal secara bersamaan
    make -j$(nproc --all) \
        ARCH=arm64 \
        O=out \
        CROSS_COMPILE=$TC64 \
        CROSS_COMPILE_ARM32=$TC32 \
        CROSS_COMPILE_COMPAT=$TC32 2>&1 | tee logs/build.txt
    
    # Mengecek apakah kompilasi berhasil
    if [ ! -f "$KIMG" ] && [ ! -f "$KIMG_DTB" ]; then
        echo -e "${red}[!] Build failed! Image not found. Check logs/build.txt for details.${white}"
        exit 1
    fi

    BUILD_END=$(TZ=Asia/Jakarta date +%s)
    DIFF=$((BUILD_END - BUILD_START))
    BUILD_TIME="$((DIFF / 60)) min $((DIFF % 60)) sec"

    echo -e "${yellow}[+] Getting kernel version...${white}"
    get_kernel_version

    ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${KERNEL_VERSION}-${DATE_TITLE}-${TIME_TITLE}.zip"
}

# =============== Zipping Kernel ===============
pack_kernel() {
    echo -e "${yellow}[+] Packing AnyKernel...${white}"

    clone_anykernel
    cd "$ANYKERNEL_DIR" || exit 1

    rm -f Image* *.zip

    if [ -f "$KIMG_DTB" ]; then
        cp "$KIMG_DTB" Image.gz-dtb
        IMG_USED="Image.gz-dtb"
    elif [ -f "$KIMG" ]; then
        cp "$KIMG" Image.gz
        IMG_USED="Image.gz"
    else
        echo -e "${red}[!] Kernel image not found in out directory!${white}"
        exit 1
    fi

    echo -e "${yellow}[+] Zipping kernel...${white}"
    zip -r9 "$ZIP_NAME" . -x ".git*" "README.md" > /dev/null
    MD5_HASH=$(md5sum "$ZIP_NAME" | awk '{print $1}')

    echo -e "\n${green}========================================${white}"
    echo -e "${green}[✓] Build & Pack Success!${white}"
    echo -e "📱 Device  : ${DEVICE}"
    echo -e "📦 Kernel  : ${KERNEL_NAME}"
    echo -e "🍃 Version : ${KERNEL_VERSION}"
    echo -e "🛠 Toolchain: ${TC_INFO}"
    echo -e "⌛ Time    : ${BUILD_TIME}"
    echo -e "🔐 MD5     : ${MD5_HASH}"
    echo -e "📁 Output  : ${ANYKERNEL_DIR}/${ZIP_NAME}"
    echo -e "${green}========================================${white}\n"
}

# ================= RUN =================
START=$(TZ=Asia/Jakarta date +%s)

setup_env
build_kernel
pack_kernel

END=$(TZ=Asia/Jakarta date +%s)
echo -e "${green}[✓] All processes completed in $((END - START)) seconds!${white}"
