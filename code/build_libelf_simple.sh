#!/bin/bash
set -e

if [ -z "$NDK_ROOT" ]; then
    export NDK_ROOT="/home/ouyang/android-toolchain/android-ndk-r26b"
fi

echo ">>> 使用 NDK: $NDK_ROOT"

TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64"
API_LEVEL=34
ARCH="aarch64-linux-android"
TARGET="${ARCH}${API_LEVEL}"

# 设置交叉编译工具
export CC="$TOOLCHAIN/bin/${TARGET}-clang"
export AR="$TOOLCHAIN/bin/llvm-ar"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"

# 目录设置
BUILD_DIR="./android_build"
ELFUTILS_SRC="elfutils-0.191"
INSTALL_DIR="$BUILD_DIR/elfutils"

mkdir -p $INSTALL_DIR/lib
mkdir -p $INSTALL_DIR/include

echo ">>> 直接编译 libelf 源文件..."

cd $ELFUTILS_SRC/libelf

# 编译所有必需的 .c 文件
SRCS="elf_version.c elf_hash.c elf_error.c elf_begin.c elf_end.c \
      elf_kind.c elf_getshdrstrndx.c elf_strptr.c elf_getident.c \
      elf_memory.c elf_fill.c elf_getdata.c elf_next.c elf_rand.c \
      elf_rawfile.c elf_cntl.c elf32_fsize.c elf64_fsize.c \
      elf32_xlatetof.c elf64_xlatetof.c elf32_xlatetom.c elf64_xlatetom.c \
      elf32_getehdr.c elf64_getehdr.c elf32_newehdr.c elf64_newehdr.c \
      elf32_getphdr.c elf64_getphdr.c elf32_newphdr.c elf64_newphdr.c \
      elf_getshdrnum.c elf32_getshdr.c elf64_getshdr.c \
      elf_flagdata.c elf_flagscn.c elf_flagehdr.c elf_flagelf.c \
      elf_flagphdr.c elf_flagshdr.c elf32_update.c elf64_update.c \
      gelf_fsize.c gelf_xlatetof.c gelf_xlatetom.c \
      gelf_getehdr.c gelf_update_ehdr.c gelf_getphdr.c gelf_update_phdr.c \
      gelf_getshdr.c gelf_update_shdr.c gelf_getsym.c gelf_update_sym.c \
      gelf_getrela.c gelf_update_rela.c gelf_getrel.c gelf_update_rel.c \
      gelf_getdyn.c gelf_update_dyn.c gelf_getmove.c gelf_update_move.c \
      gelf_getsymshndx.c gelf_update_symshndx.c gelf_getverdaux.c \
      gelf_getverdef.c gelf_getvern aux.c gelf_getverneed.c \
      gelf_getversym.c gelf_update_versym.c gelf_getchdr.c gelf_update_chdr.c"

OBJS=""
for src in $SRCS; do
    if [ -f "$src" ]; then
        obj="${src%.c}.o"
        echo "  编译 $src..."
        $CC -fPIC -O2 \
            -I. -I../lib -I../libelf -I.. -I../config \
            -DHAVE_CONFIG_H \
            -D_GNU_SOURCE \
            -c $src -o $obj 2>/dev/null || echo "    警告: $src 编译失败"
        if [ -f "$obj" ]; then
            OBJS="$OBJS $obj"
        fi
    fi
done

# 创建静态库
echo ">>> 创建 libelf.a..."
$AR rcs ../../$INSTALL_DIR/lib/libelf.a $OBJS
$RANLIB ../../$INSTALL_DIR/lib/libelf.a

# 复制头文件
echo ">>> 复制头文件..."
cp -f libelf.h gelf.h elf-knowledge.h ../../$INSTALL_DIR/include/ 2>/dev/null || true
cp -f ../lib/eu-config.h ../../$INSTALL_DIR/include/ 2>/dev/null || true
cp -f ../version.h ../../$INSTALL_DIR/include/ 2>/dev/null || true

cd ../..

echo ">>> ✅ libelf 编译完成！"
ls -lh $INSTALL_DIR/lib/libelf.a
ls $INSTALL_DIR/include/
