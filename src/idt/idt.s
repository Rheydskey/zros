[bits 64]

load_idt:
    lidt [rdi]

    retfq

global load_idt
