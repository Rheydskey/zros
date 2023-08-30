[bits 64]

load_idt:
    lidt [rdi]
    retq

global load_idt
