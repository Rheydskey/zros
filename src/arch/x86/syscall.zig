const utils = @import("root").utils;
const Regs = @import("idt/interrupt.zig").Regs;
const serial = @import("root").drivers.serial;
const screen = @import("../../drivers/fbscreen.zig").screen;
const Msr = utils.Msr;

extern fn prepare_syscall_handler() void;

pub fn load_ring_3(stack: u64, code: u64) noreturn {
    asm volatile (
        \\ push $0x23 // user ss 
        \\ push %[stack]
        \\ push $0x202 // rflags
        \\ push $0x1B // user cs
        \\ push %[code]
        \\ iretq
        :
        : [stack] "r" (stack),
          [code] "r" (code),
    );

    unreachable;
}

// https://github.com/brutal-org/brutal/blob/d458fa9ca9d7b88dd62dbbc715bf02feaca21d99/sources/kernel/x86_64/syscall.c
pub fn init() void {
    Msr.write(Msr.Regs.EFER, Msr.Efer.SYSCALL | Msr.Efer.LONGMODE);
    // KERNEL_CODE * 8 << 32 | (((USER_DATA - 1) * 8 | RING_3) << 48)
    const star_value: u64 = 8 << 32 | ((16 * 8 | 3) << 48);

    Msr.write(Msr.Regs.STAR, star_value);
    Msr.write(Msr.Regs.LSTAR, @intFromPtr(&prepare_syscall_handler));
    Msr.write(Msr.Regs.SYSCALL_FLAGS, 0xFFFF_FFFE);
}

pub fn setGs(addr: usize) void {
    Msr.write(Msr.Regs.GS_BASE, addr);
    Msr.write(Msr.Regs.KERN_GS_BASE, addr);
}

const SyscallId = enum(u8) {
    Baka = 0x0,
    Uwu = 0x1,
    _,
};

export fn syscallHandler(registers: *Regs) callconv(.C) void {
    const syscall_id: SyscallId = @enumFromInt(registers.rax);
    switch (syscall_id) {
        .Uwu => serial.println_nolock("UWU !!", .{}),
        else => serial.println_nolock("BAKA !!", .{}),
    }
}
