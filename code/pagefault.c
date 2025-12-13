// pagefault.c
#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>
#include <errno.h>
#include </home/ouyang/libbpf-bootstrap/libbpf/src/libbpf.h>
#include "pagefault.h"
#include "pagefault.skel.h" // 编译时自动生成的头文件

static int stop = 0;

static void sig_int(int signo) {
    stop = 1;
}

// 回调函数：处理 Ring Buffer 传来的数据
static int handle_event(void *ctx, void *data, size_t data_sz) {
    const struct event *e = data;
    
    printf("[PID: %-6d] [Comm: %-16s] Fault on File: %-20s (Offset: 0x%-10lx) VAddr: 0x%lx\n",
           e->pid, e->comm, e->filename, e->file_offset, e->vaddr);
    return 0;
}

int main(int argc, char **argv) {
    struct pagefault_bpf *skel;
    struct ring_buffer *rb = NULL;
    int err;

    // 处理 Ctrl+C 退出
    signal(SIGINT, sig_int);

    // 1. 打开 BPF 程序骨架
    skel = pagefault_bpf__open();
    if (!skel) {
        fprintf(stderr, "Failed to open BPF skeleton\n");
        return 1;
    }

    // 2. 加载并验证
    err = pagefault_bpf__load(skel);
    if (err) {
        fprintf(stderr, "Failed to load BPF skeleton\n");
        goto cleanup;
    }

    // 3. 挂载到内核函数 (Attach)
    err = pagefault_bpf__attach(skel);
    if (err) {
        fprintf(stderr, "Failed to attach BPF skeleton\n");
        goto cleanup;
    }

    // 4. 设置 Ring Buffer 轮询
    rb = ring_buffer__new(bpf_map__fd(skel->maps.rb), handle_event, NULL, NULL);
    if (!rb) {
        err = -1;
        fprintf(stderr, "Failed to create ring buffer\n");
        goto cleanup;
    }

    printf("Successfully started! Monitoring Page Faults on Pixel 8...\n");
    printf("Ctrl+C to stop.\n");

    // 5. 循环读取
    while (!stop) {
        err = ring_buffer__poll(rb, 100 /* timeout ms */);
        if (err == -EINTR) {
            err = 0;
            break;
        }
        if (err < 0) {
            printf("Error polling perf buffer: %d\n", err);
            break;
        }
    }

cleanup:
    ring_buffer__free(rb);
    pagefault_bpf__destroy(skel);
    return -err;
}