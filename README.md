# 一、 配置开发环境

1. 下载 libbpf-bootstrap 脚手架，这是开发 eBPF 工具的标准起点。
- git clone --recurse-submodules https://github.com/libbpf/libbpf-bootstrap
- cd libbpf-bootstrap/examples/c

2. 记得换源，推荐阿里云源，不然会很慢
deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-proposed main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ jammy-proposed main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse






# 二、获取 Pixel 8 的内核类型定义 (vmlinux.h) 和 BPF 骨架 (pagefault.skel.h) 并将其转换为 C 语言头文件。
这是 CO-RE 的核心。我们需要从你的手机中提取内核数据结构定义。

进入linux系统（原生系统/虚拟机），以下所有的操作都最好在linux环境中进行

1. 配置好环境变量，确保 bpftool 和 clang 可用。
- sudo apt install clang llvm make gcc libelf-dev flex bison -y

2. 下载需要的两个核心工具：adb 和 bpftool。
    - sudo apt install android-tools-adb   
    - sudo apt install linux-tools-common linux-tools-generic  
    或者     
    - sudo apt install bpftool
    #bpftool工具的安装路径通常是 /usr/bin/bpftool 或者 /usr/lib/linux-tools/版本号/bpftool

3.  从 Pixel 8手机 提取二进制文件（目标文件：/sys/kernel/btf/vmlinux） 传输到 linux电脑。
使用 adb shell 获取 root 权限并读取文件，重定向到电脑的当前目录
- adb shell "su -c 'cat /sys/kernel/btf/vmlinux'" > vmlinux_pixel8_binary

4. 验证文件：查看文件大小，它通常在 4MB - 10MB 之间。
- ls -lh vmlinux_pixel8_binary

5. 在linux电脑上将刚才拉下来的二进制文件转换为 C 语言头文件
- bpftool btf dump file vmlinux_pixel8_binary format c > vmlinux.h

6. 现在你的目录下有了一个 vmlinux.h，文件很大，有几万行，然后将生成的 vmlinux.h 放入 libbpf-bootstrap/examples/c 目录下。
- scp -P 10226 "E:\1\vmlinux.h" ouyang@47.108.143.39:/home/ouyang/libbpf-bootstrap/examples/c



# 三、编译eBPF程序步骤——三步走

记得改pagefault.bpf.c的头文件地址：
    #include </home/ouyang/libbpf-bootstrap/libbpf/src/bpf_helpers.h>
    #include </home/ouyang/libbpf-bootstrap/libbpf/src/bpf_tracing.h>
    #include </home/ouyang/libbpf-bootstrap/libbpf/src/bpf_core_read.h>

1. 第一步：编译内核态代码 (生成 .o 文件)
首先，编译器需要把你的 C 语言内核代码 (pagefault.bpf.c) 编译成 BPF 字节码。
前提：确保你的目录下已经有了 vmlinux.h (之前从手机里提取的) 和 pagefault.bpf.c。
- clang -g -O2 -target bpf -D__TARGET_ARCH_arm64 -I. -c pagefault.bpf.c -o pagefault.bpf.o


2. 第二步：生成骨架头文件 (生成 .skel.h) 
这一步是 eBPF 开发的“魔法”。我们需要用 bpftool 读取刚才生成的 .o 文件，把它转换成一个 C 语言头文件。
- bpftool gen skeleton pagefault.bpf.o > pagefault.skel.h

3. 第三步：编译用户态加载器 (生成可执行文件)
现在，头文件有了，你终于可以编译 pagefault.c 了。
注意：这一步是交叉编译，为了让它能在 Android (Pixel 8) 上运行，你需要使用 NDK 的 Clang。
- cd /home/ouyang/libbpf-bootstrap/examples/c && rm -f pagefault.bpf.o pagefault.skel.h pagefault_monitor && ./build_android.sh

## tip： 此过程中将遇到一个问题：libbpf 的核心功能（解析 BPF 对象文件、CO-RE 重定位）严重依赖 libelf 库。虽然 NDK 提供了基础的 C 库，但 NDK 并不包含 libelf。而且，我们不能简单地禁用它，否则编译出来的程序无法加载 BPF 代码。所以，需要我们手动下载并编译一个适用于 Android 的 libelf。
### 解决方案
问题的根本原因是 libbpf 依赖 libelf 库,而 Android NDK 默认不提供这个库。我通过以下步骤解决了这个问题:

1. 下载并配置 elfutils-0.191 - 包含 libelf 库的源代码

2. 修复编译兼容性问题:
    * 禁用了国际化支持 (libintl) 来避免 Android 缺少的依赖
    * 修改 eu-config.h 文件注释掉 #include <libintl.h>

3. 为 Android 交叉编译 libelf:
    * 创建了 build_libelf_android.sh 脚本
    * 使用 Android NDK 的 clang 编译器编译所有 libelf 源文件
    * 生成了静态库 libelf.a (286KB)

4. 更新构建脚本:
    * 在 build_android.sh 中添加 libelf 的头文件和库文件路径
    * 添加 -D__poll_t=unsigned 来解决 Android NDK 兼容性问题
    * 使用 BUILD_STATIC_ONLY=y 只编译静态库

5. 修复用户态代码:
    * 创建共享头文件 pagefault.h 定义 struct event
    * 在 BPF 和用户态代码中都包含这个头文件


# 四、 使用eBPF程序
第一步：检查并挂载 Debugfs 
1. 检查是否已挂载
- mount | grep debugfs
2. 如果没有输出，执行挂载命令：
mount -t debugfs debugfs /sys/kernel/debug
- chmod 755 /sys/kernel/debug

第二步：将编译好的 eBPF 程序推送到 Pixel 8，并运行你的 eBPF 程序
- adb push E:\1\pagefault_monitor /data/local/tmp/
- cd /data/local/tmp
- chmod +x pagefault_monitor
- ./pagefault_monitor



