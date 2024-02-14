pub inline fn align_up(addr: usize, alignment: usize) usize {
    return (addr + alignment - 1) & ~(alignment - 1);
}

pub inline fn align_down(addr: usize, alignment: usize) usize {
    return (addr) & ~(alignment - 1);
}

pub fn read_cr0() u64 {
    return asm volatile ("mov %%cr0, %[cr0]"
        : [cr0] "=r" (-> u64),
    );
}

pub fn write_cr0(value: usize) void {
    asm volatile ("mov %[value], %%cr0"
        :
        : [value] "{rax}" (value),
    );
}
