const serial = @import("./drivers/serial.zig");

pub inline fn align_up(addr: usize, alignment: usize) usize {
    return (addr + alignment - 1) & ~(alignment - 1);
}

pub inline fn align_down(addr: usize, alignment: usize) usize {
    return (addr) & ~(alignment - 1);
}

pub inline fn is_align(addr: usize, alignment: usize) bool {
    return align_down(addr, alignment) == addr;
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

pub const Msr = struct {
    pub const EFER_ENABLE_SYSCALL = 1;

    pub const Regs = struct {
        pub const APIC = 0x1B;
        pub const EFER = 0xC000_0080;
        pub const STAR = 0xC000_0081;
        pub const LSTAR = 0xC000_0082;
        pub const COMPAT_STAR = 0xC000_0083;
        pub const SYSCALL_FLAGS = 0xC000_0084;
        pub const FS_BASE = 0xC000_0100;
        pub const GS_BASE = 0xC000_0101;
        pub const KERN_GS_BASE = 0xC000_0102;
    };

    pub fn read(msr: u64) u64 {
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

    pub fn write(msr: u64, value: u64) void {
        const low: u32 = @intCast(value);
        const high: u32 = @intCast(value >> 32);
        asm volatile ("wrmsr"
            :
            : [_] "{rcx}" (msr),
              [_] "{eax}" (low),
              [_] "{edx}" (high),
        );
    }
};

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
        if (@sizeOf(cmp) != expected_size) {
            @compileError(comptimePrint("Bad size({} instead of {}) for " ++ @typeName(cmp), .{ @sizeOf(cmp), expected_size }));
        }
    }
}
