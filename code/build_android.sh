#!/bin/bash
set -e # 遇到错误立即停止执行

# === 0. 检查路径配置 ===
if [ -z "$NDK_ROOT" ]; then
    export NDK_ROOT="/home/ouyang/android-toolchain/android-ndk-r26b"
fi

echo ">>> 使用 NDK: $NDK_ROOT"

# 定义编译器变量
CLANG="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
LLVM_STRIP="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
# 添加 __poll_t 定义来解决 Android NDK 兼容性问题
ARCH_CFLAGS="-target aarch64-linux-android34 -D__poll_t=unsigned"

# 定义目录变量
LIBBPF_SRC="../../libbpf/src"
BUILD_DIR="./android_build"
mkdir -p $BUILD_DIR

# === 0.5 编译 libelf for Android ===
ELFUTILS_DIR="$BUILD_DIR/elfutils"
if [ ! -f "$ELFUTILS_DIR/lib/libelf.a" ]; then
    echo ">>> [0/4] 正在为 Android 编译 libelf..."
    ./build_libelf_android.sh
else
    echo ">>> [0/4] libelf 已存在，跳过编译。"
fi

# === 1. 交叉编译 libbpf.a (核心步骤) ===
if [ ! -f "$BUILD_DIR/root/usr/lib64/libbpf.a" ]; then
    echo ">>> [1/4] 正在为 Android ARM64 编译 libbpf..."
    
    # 添加 libelf 的头文件和库文件路径
    # 只编译静态库，不编译共享库
    make -C $LIBBPF_SRC \
        CC="$CLANG" \
        EXTRA_CFLAGS="$ARCH_CFLAGS -I$(pwd)/$ELFUTILS_DIR/include" \
        EXTRA_LDFLAGS="-L$(pwd)/$ELFUTILS_DIR/lib" \
        DESTDIR="$(pwd)/$BUILD_DIR/root" \
        OBJDIR="$(pwd)/$BUILD_DIR/libbpf_obj" \
        NO_PKG_CONFIG=1 \
        BUILD_STATIC_ONLY=y \
        install
        
else
    echo ">>> [1/4] libbpf 已存在，跳过编译。"
fi

# === 2. 编译 BPF 内核态代码 (.o) ===
echo ">>> [2/4] 编译 BPF 内核代码..."
clang -g -O2 -target bpf -D__TARGET_ARCH_arm64 -I. -c pagefault.bpf.c -o pagefault.bpf.o

# === 3. 生成 Skeleton 头文件 (.skel.h) ===
echo ">>> [3/4] 生成 Skeleton 头文件..."
bpftool gen skeleton pagefault.bpf.o > pagefault.skel.h

# === 4. 交叉编译用户态程序 (Linking) ===
echo ">>> [4/4] 编译最终可执行文件 pagefault_monitor..."

$CLANG $ARCH_CFLAGS \
    -O2 -g \
    -I. \
    -I$BUILD_DIR/root/usr/include \
    -I$ELFUTILS_DIR/include \
    -o pagefault_monitor \
    pagefault.c \
    $BUILD_DIR/root/usr/lib64/libbpf.a \
    $ELFUTILS_DIR/lib/libelf.a \
    -lz \
    -static

# 瘦身 (Strip)
$LLVM_STRIP -s pagefault_monitor

echo ">>> ✅ 编译成功！"
echo ">>> 文件位置: $(pwd)/pagefault_monitor"
echo ">>> 架构检查: $(file pagefault_monitor)"