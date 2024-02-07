[bits 64]

idt_load:
    lidt [rdi]
    ret

global idt_load
