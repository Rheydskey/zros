const serial = @import("./drivers/serial.zig");

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

pub fn read_msr(msr: u64) u64 {
    var low: u32 = 0;
    var high: u32 = 0;

    asm volatile ("rdmsr"
        : [low] "=rax" (low),
          [high] "=rdx" (high),
        : [msr] "{rcx}" (msr),
        : "=r"
    );

    return @as(u64, @intCast(high)) << 32 | low;
}

pub fn checkSize(cmp: type, expected_size: u64) void {
    comptime {
        const comptimePrint = @import("std").fmt.comptimePrint;
        if (!(@sizeOf(cmp) == expected_size)) {
            @compileError(comptimePrint("Bad size({} instead of {}) for " ++ @typeName(cmp), .{ @sizeOf(cmp), expected_size }));
        }
    }
}
