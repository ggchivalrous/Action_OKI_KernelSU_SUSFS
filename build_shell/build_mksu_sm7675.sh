#!/usr/bin/env bash
set -xve

# 获取 GitHub Actions 传入的参数
MANIFEST_FILE="$1"
ENABLE_LTO="$2"
ENABLE_POLLY="$3"
ENABLE_O3="$4"

# 根据 manifest_file 映射 CPUD
case "$MANIFEST_FILE" in
    "oneplus_ace_3v_v" | "oneplus_nord_4_v")
        CPUD="pineapple"
        ;;
    *)
        echo "Error: Unsupported manifest_file: $MANIFEST_FILE"
        exit 1
        ;;
esac

# 设置版本变量
ANDROID_VERSION="android14"
KERNEL_VERSION="6.1"

# 设置工作目录
OLD_DIR="$(pwd)"
KERNEL_WORKSPACE="$OLD_DIR/kernel_platform"

# 配置编译器自然环境
export CC="clang"
export CLANG_TRIPLE="aarch64-linux-gnu-"
export LDFLAGS="-fuse-ld=lld"

# 根据参数设置优化标志
BAZEL_ARGS=""
[ "$ENABLE_O3" = "true" ] && BAZEL_ARGS="$BAZEL_ARGS --copt=-O3 --copt=-Wno-error"
[ "$ENABLE_LTO" = "true" ] && BAZEL_ARGS="$BAZEL_ARGS --copt=-flto --linkopt=-flto"
[ "$ENABLE_POLLY" = "true" ] && BAZEL_ARGS="$BAZEL_ARGS --copt=-mllvm --copt=-polly --copt=-mllvm --copt=-polly-vectorizer=stripmine"

# 清理旧的保护导出文件
rm -f "$KERNEL_WORKSPACE/common/android/abi_gki_protected_exports_*" || echo "No protected exports!"
rm -f "$KERNEL_WORKSPACE/msm-kernel/android/abi_gki_protected_exports_*" || echo "No protected exports!"
sed -i 's/ -dirty//g' "$KERNEL_WORKSPACE/build/kernel/kleaf/workspace_status_stamp.py"

# 检查完整目录结构
cd "$KERNEL_WORKSPACE" || exit 1
find . -type d > "$OLD_DIR/kernel_directory_structure.txt"

# 设置 KernelSU (官方原版)
cd "$KERNEL_WORKSPACE" || exit 1
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
cd KernelSU || exit 1
KSU_VERSION=$(expr "$(git rev-list --count HEAD)" + 10200)
sed -i "s/DKSU_VERSION=16/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile

cd "$KERNEL_WORKSPACE" || exit 1

# 这一步用于修复lz4与zstd 所导致的WiFi 5G失效等一系列问题
rm common/android/abi_gki_protected_exports_*     

echo "CONFIG_TMPFS_XATTR=y" >> "$KERNEL_WORKSPACE/common/arch/arm64/configs/gki_defconfig"
echo "CONFIG_TMPFS_POSIX_ACL=y" >> "$KERNEL_WORKSPACE/common/arch/arm64/configs/gki_defconfig"

sed -i 's/check_defconfig//' "$KERNEL_WORKSPACE/common/build.config.gki"

export OPLUS_FEATURES="OPLUS_FEATURE_BSP_DRV_INJECT_TEST=1"
# 构建内核
cd "$OLD_DIR" || exit 1
./kernel_platform/build_with_bazel.py -t "${CPUD}" gki \
    --config=stamp \
    --linkopt="-fuse-ld=lld" \
    $BAZEL_ARGS

# 获取内核版本
KERNEL_VERSION=$(cat "$KERNEL_WORKSPACE/out/msm-kernel-${CPUD}-gki/dist/version.txt" 2>/dev/null || echo "6.1")

# 输出变量到 GitHub Actions
echo "kernel_version=$KERNEL_VERSION" >> "$GITHUB_OUTPUT"
echo "ksu_version=$KSU_VERSION" >> "$GITHUB_OUTPUT"