[bits 64]

section .text
global disable_paging

disable_paging:
  mov rbx, cr0
  and rbx, ~(1 << 31)
  mov cr0, rbx
