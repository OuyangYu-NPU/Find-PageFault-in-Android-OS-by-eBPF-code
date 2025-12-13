#include "vmlinux.h"
#include </home/ouyang/libbpf-bootstrap/libbpf/src/bpf_helpers.h>
#include </home/ouyang/libbpf-bootstrap/libbpf/src/bpf_tracing.h>
#include </home/ouyang/libbpf-bootstrap/libbpf/src/bpf_core_read.h>

char LICENSE[] SEC("license") = "Dual BSD/GPL";

struct event {
    int pid;
    char comm[16];
    char filename[32];
    unsigned long file_offset;
    unsigned long vaddr;
};

struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 256 * 1024);
} rb SEC(".maps");

// 重点：filemap_fault 的参数通常是 struct vm_fault *vmf
// 我们可以通过 vmlinux.h 确认：vm_fault_t filemap_fault(struct vm_fault *vmf);
SEC("kprobe/filemap_fault")
int BPF_KPROBE(filemap_fault, struct vm_fault *vmf)
{
    struct event *e;
    struct vm_area_struct *vma;
    struct file *fp;
    unsigned long address;

    // 1. 从参数 vmf 中提取 vma 和 address
    vma = BPF_CORE_READ(vmf, vma);
    address = BPF_CORE_READ(vmf, address);

    // 2. 既然进了 filemap_fault，理论上一定有文件，但为了安全检查一下
    fp = BPF_CORE_READ(vma, vm_file);
    if (!fp) return 0;

    e = bpf_ringbuf_reserve(&rb, sizeof(*e), 0);
    if (!e) return 0;

    // 3. 采集信息
    e->pid = bpf_get_current_pid_tgid() >> 32;
    bpf_get_current_comm(&e->comm, sizeof(e->comm));

    // 获取文件名
    struct dentry *dentry = BPF_CORE_READ(fp, f_path.dentry);
    const unsigned char *name_ptr = BPF_CORE_READ(dentry, d_name.name);
    bpf_probe_read_kernel_str(&e->filename, sizeof(e->filename), name_ptr);

    // 4. 计算 Offset
    // 注意：这里必须重新读取 vma 里的 start 和 pgoff
    unsigned long vm_start = BPF_CORE_READ(vma, vm_start);
    unsigned long vm_pgoff = BPF_CORE_READ(vma, vm_pgoff);
    
    // Pixel 8 ARM64 页大小 4KB (12位)
    e->file_offset = (address - vm_start) + (vm_pgoff << 12);
    e->vaddr = address;

    bpf_ringbuf_submit(e, 0);
    return 0;
}