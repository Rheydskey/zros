pub inline fn align_up(addr: usize, alignment: usize) usize {
    return (addr + alignment - 1) & ~(alignment - 1);
}

pub inline fn align_down(addr: usize, alignment: usize) usize {
    return (addr) & ~(alignment - 1);
}
