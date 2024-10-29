[BITS 64]

push r10
a:
mov r10, 0xCAFE
mov rax, 1
syscall
jmp a
pop r10
