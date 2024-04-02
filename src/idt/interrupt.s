[bits 64]
%macro push_all 0
        push rax
        push rcx
        push rdx
        push rbx
        push rsp
        push rbp
        push rsi
        push rdi
        
%endmacro

%macro pop_all 0
        pop rdi
        pop rsi
        pop rbp
        pop rsp
        pop rbx
        pop rdx
        pop rcx
        pop rax
%endmacro


%macro INTERRUPT_ERR 1
interrupt_%1:
        push qword %1
        jmp interrupt_common
                        
%endmacro

%macro INTERRUPT_NOERR 1
interrupt_%1:
        push qword 0
        push qword %1
        jmp interrupt_common
                        
%endmacro


extern interrupt_handler

interrupt_common:
        cld
        push_all

        mov rdi, rsp
        call interrupt_handler
        mov rsp, rax

        pop_all

        add rsp, 16 ; clear error code and interrupt number

        iretq

INTERRUPT_NOERR 0
INTERRUPT_NOERR 1
INTERRUPT_NOERR 2
INTERRUPT_NOERR 3
INTERRUPT_NOERR 4
INTERRUPT_NOERR 5
INTERRUPT_NOERR 6
INTERRUPT_NOERR 7
INTERRUPT_ERR   8
INTERRUPT_NOERR 9
INTERRUPT_ERR   10
INTERRUPT_ERR   11
INTERRUPT_ERR   12
INTERRUPT_ERR   13
INTERRUPT_ERR   14
INTERRUPT_NOERR 15
INTERRUPT_NOERR 16
INTERRUPT_ERR   17
INTERRUPT_NOERR 18
INTERRUPT_NOERR 19
INTERRUPT_NOERR 20
INTERRUPT_NOERR 21
INTERRUPT_NOERR 22
INTERRUPT_NOERR 23
INTERRUPT_NOERR 24
INTERRUPT_NOERR 25
INTERRUPT_NOERR 26
INTERRUPT_NOERR 27
INTERRUPT_NOERR 28
INTERRUPT_NOERR 29
INTERRUPT_ERR   30
INTERRUPT_NOERR 31

%assign i 32
%rep 224
    INTERRUPT_NOERR i
%assign i i+1
%endrep


%macro INTERRUPT_NAME 1

    dq interrupt_%1

%endmacro

section .data
global interrupt_vector
%define idt_size 256

interrupt_vector:
%assign i 0
%rep idt_size
    INTERRUPT_NAME i
%assign i i+1
%endrep

