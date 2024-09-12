[BITS 64]

push r10
a:
mov r10, 0xCAFE
syscall

jmp a
pop r10
