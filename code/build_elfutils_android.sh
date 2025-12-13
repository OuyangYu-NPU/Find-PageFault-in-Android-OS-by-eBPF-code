#!/bin/bash
set -e

# === 配置 ===
if [ -z "$NDK_ROOT" ]; then
    export NDK_ROOT="/home/ouyang/android-toolchain/android-ndk-r26b"
fi

echo ">>> 使用 NDK: $NDK_ROOT"

TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64"
API_LEVEL=34
ARCH="aarch64-linux-android"
TARGET="${ARCH}${API_LEVEL}"

# 设置编译器
export CC="$TOOLCHAIN/bin/${TARGET}-clang"
export CXX="$TOOLCHAIN/bin/${TARGET}-clang++"
export AR="$TOOLCHAIN/bin/llvm-ar"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$TOOLCHAIN/bin/llvm-strip"

# 设置 CFLAGS
export CFLAGS="-fPIC -O2 -D_GNU_SOURCE"
export CXXFLAGS="-fPIC -O2"

# 构建目录
ELFUTILS_DIR="elfutils-0.191"
BUILD_DIR="./android_build"
INSTALL_PREFIX="$BUILD_DIR/elfutils"

mkdir -p $INSTALL_PREFIX

# 先构建 argp-standalone
ARGP_DIR="argp-standalone-1.3"
if [ ! -f "$ARGP_DIR.tar.gz" ]; then
    echo ">>> 下载 argp-standalone..."
    wget http://www.lysator.liu.se/~nisse/misc/argp-standalone-1.3.tar.gz
    tar xf argp-standalone-1.3.tar.gz
fi

if [ ! -f "$INSTALL_PREFIX/lib/libargp.a" ]; then
    echo ">>> 编译 argp-standalone..."
    cd $ARGP_DIR
    
    # 清理
    if [ -f Makefile ]; then
        make clean || true
    fi
    
    # 配置和编译
    ./configure --host=${ARCH} --prefix=$PWD/../$INSTALL_PREFIX
    make
    make install
    
    cd ..
fi

echo ">>> 配置 elfutils for Android..."
cd $ELFUTILS_DIR

# 清理之前的构建
if [ -f Makefile ]; then
    make clean || true
fi

# 配置编译（只编译 libelf）
CFLAGS="$CFLAGS -I$PWD/../$INSTALL_PREFIX/include" \
LDFLAGS="-L$PWD/../$INSTALL_PREFIX/lib" \
./configure \
    --host=${ARCH} \
    --prefix=$PWD/../$INSTALL_PREFIX \
    --disable-debuginfod \
    --disable-libdebuginfod \
    --enable-maintainer-mode \
    --disable-demangler \
    --without-zstd \
    --without-lzma \
    --without-bzlib \
    ac_cv_func_mempcpy=yes

echo ">>> 编译 libelf..."
# 只编译 libelf，不编译其他工具
cd libelf
make

echo ">>> 安装 libelf..."
make install

cd ../..

echo ">>> ✅ elfutils (libelf) 编译完成！"
echo ">>> 头文件位置: $INSTALL_PREFIX/include"
echo ">>> 库文件位置: $INSTALL_PREFIX/lib"
ls -lh $INSTALL_PREFIX/lib/libelf.* 2>/dev/null || ls -lh $INSTALL_PREFIX/lib/
