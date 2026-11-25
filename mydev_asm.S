.intel_syntax noprefix

/* Kernel symbols we call */
.extern _printk
.extern alloc_chrdev_region
.extern cdev_init
.extern cdev_add
.extern cdev_del
.extern class_create
.extern class_destroy
.extern device_create
.extern device_destroy
.extern unregister_chrdev_region
.extern mydev_copy_to_user
.extern mydev_copy_from_user

/* from mydev_main.c */
.extern mydev_get_devno_addr
.extern mydev_get_cdev_addr
.extern mydev_get_fops
.extern mydev_get_class_addr
.extern mydev_set_cdev_owner

.section .rodata
.str_mydev:     .asciz "mydev"
.str_loaded:    .asciz "mydev: loaded\n"
.str_unloaded:  .asciz "mydev: unloaded\n"

.section .bss
.align 8
mydev_buf:       .skip 256
mydev_buf_len:   .skip 8
mydev_read_pos:  .skip 8


.section .text
.globl mydev_open 
mydev_open:
    mov qword ptr [rip + mydev_read_pos], 0
    xor eax, eax
    ret
.size mydev_open, .-mydev_open


.globl mydev_release 
mydev_release:
    xor eax, eax
    ret
.size mydev_release, .-mydev_release

.globl mydev_read
mydev_read:
    push rbp
    mov  rbp, rsp
    push r12
    push r13

    mov  r12, rsi               /* ubuf */
    mov  r13, rdx               /* count */
    mov  rax, [rip + mydev_buf_len]
    mov  rdx, [rip + mydev_read_pos]
    sub  rax, rdx
    test rax, rax
    jle  .read_eof
    cmp  r13, rax
    jbe  .read_n_ok
    mov  r13, rax
.read_n_ok:
    /* mydev_copy_to_user */
    mov  rdi, r12
    lea  rsi, [rip + mydev_buf]
    mov  rdx, [rip + mydev_read_pos]
    add  rsi, rdx
    mov  rdx, r13
    call mydev_copy_to_user
    test rax, rax
    jnz  .read_fault
    mov  rax, [rip + mydev_read_pos]
    add  rax, r13
    mov  [rip + mydev_read_pos], rax
    mov  rax, r13
    jmp  .read_done

.read_eof:
    xor  eax, eax
    jmp  .read_done

.read_fault:
    mov  rax, -14              

.read_done:
    pop  r13
    pop  r12
    pop  rbp
    ret
.size mydev_read, .-mydev_read

.globl mydev_write
mydev_write:
    push rbp
    mov  rbp, rsp
    push r12
    push r13

    mov  r12, rsi               /* ubuf */
    mov  r13, rdx               /* count */

    cmp  r13, 256
    jbe  .write_size_ok
    mov  r13, 256
.write_size_ok:
    /* mydev_copy_from_user*/
    lea  rdi, [rip + mydev_buf]
    mov  rsi, r12
    mov  rdx, r13
    call mydev_copy_from_user
    test rax, rax
    jnz  .write_fault
    mov  [rip + mydev_buf_len], r13
    mov  qword ptr [rip + mydev_read_pos], 0
    mov  rax, r13
    jmp  .write_done

.write_fault:
    mov  rax, -14               

.write_done:
    pop  r13
    pop  r12
    pop  rbp
    ret
.size mydev_write, .-mydev_write


.globl mydev_init_asm
mydev_init_asm:
    push rbp
    mov  rbp, rsp
    push r12
    push r13
    push r14

    call mydev_get_devno_addr
    mov  r12, rax               /* r12 = &devno */
    call mydev_get_cdev_addr
    mov  r13, rax               /* r13 = &cdev */
    call mydev_get_class_addr
    mov  r14, rax               /* r14 = &class_ptr */

    /* alloc_chrdev_region*/
    mov  rdi, r12
    xor  rsi, rsi
    mov  rdx, 1
    lea  rcx, [rip + .str_mydev]
    call alloc_chrdev_region
    test eax, eax
    js   .init_fail

    /* cdev_init*/
    mov  rdi, r13
    call mydev_get_fops
    mov  rsi, rax
    call cdev_init
    mov  rdi, r13
    call mydev_set_cdev_owner

    /* cdev_add */
    mov  rdi, r13
    mov  rsi, [r12]
    mov  rdx, 1
    call cdev_add
    test eax, eax
    js   .init_err_unreg

    /* class_create */
    lea  rdi, [rip + .str_mydev]
    call class_create
    cmp  rax, -4095             /* IS_ERR */
    jae  .init_err_cdev
    mov  [r14], rax

    /* device_create */
    mov  rdi, [r14]
    xor  rsi, rsi
    mov  rdx, [r12]
    xor  rcx, rcx
    lea  r8,  [rip + .str_mydev]
    call device_create
    cmp  rax, -4095
    jae  .init_err_class

    /* success */
    lea  rdi, [rip + .str_loaded]
    call _printk
    xor  eax, eax
    jmp  .init_done

.init_err_class:
    mov  rdi, [r14]
    call class_destroy
    mov  qword ptr [r14], 0
.init_err_cdev:
    mov  rdi, r13
    call cdev_del
.init_err_unreg:
    mov  rdi, [r12]
    mov  rsi, 1
    call unregister_chrdev_region
    mov  eax, -19               
    jmp  .init_done

.init_fail:

.init_done:
    pop  r14
    pop  r13
    pop  r12
    pop  rbp
    ret
.size mydev_init_asm, .-mydev_init_asm

/* mydev_exit_asm */
.globl mydev_exit_asm
mydev_exit_asm:
    push rbp
    mov  rbp, rsp
    push r12
    push r13
    push r14

    call mydev_get_devno_addr
    mov  r12, rax
    call mydev_get_cdev_addr
    mov  r13, rax
    call mydev_get_class_addr
    mov  r14, rax

    /* device_destroy */
    mov  rdi, [r14]
    mov  rsi, [r12]
    call device_destroy

    /* class_destroy */
    mov  rdi, [r14]
    call class_destroy

    /* cdev_del */
    mov  rdi, r13
    call cdev_del

    /* unregister_chrdev_region */
    mov  rdi, [r12]
    mov  rsi, 1
    call unregister_chrdev_region

    lea  rdi, [rip + .str_unloaded]
    call _printk

    pop  r14
    pop  r13
    pop  r12
    pop  rbp
    ret
.size mydev_exit_asm, .-mydev_exit_asm



