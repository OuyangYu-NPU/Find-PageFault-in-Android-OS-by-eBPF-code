// pagefault.h - 共享的数据结构定义
#ifndef __PAGEFAULT_H
#define __PAGEFAULT_H

// 定义回传给用户态的数据结构
struct event {
    int pid;
    char comm[16];
    char filename[32];
    unsigned long file_offset;
    unsigned long vaddr;
};

#endif /* __PAGEFAULT_H */
