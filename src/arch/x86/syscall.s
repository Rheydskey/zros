; https://github.com/brutal-org/brutal/blob/main/sources/kernel/x86_64/syscall.s
; https://cyp.sh/blog/syscallsysret

[BITS 64]

%macro push_all 0

    push rax
    push rbx
    push rcx
    push rdx
    push rbp
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

%endmacro

%macro pop_all 0

    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rbp
    pop rdx
    pop rcx
    pop rbx

%endmacro

global prepare_syscall_handler
prepare_syscall_handler:
    swapgs
    mov [gs:0x8], rsp       ; gs.saved_stack = rsp
    mov rsp, [gs:0x0]       ; rsp = gs.syscall_stack

    sti

    ; push information (gs, cs, rip, rflags, rip...)
    push qword 0x23         ; user data segment
    push qword [gs:0x8]     ; saved stack
    push r11                ; saved rflags
    push qword 0x1B         ; user code segment
    push rcx                ; current RIP

    push_all                ; push every register

    mov rdi, rsp            ; put the stackframe as the syscall argument
    mov rbp, 0

    extern syscallHandler
    call syscallHandler ; jump to beautiful higher level code

    pop_all ; pop every register except RAX as we use it for the return value

    cli

    mov rsp, [gs:0x8]
    swapgs
    o64 sysret
