const idt = @import("../idt.zig");
const serial = @import("../drivers/serial.zig");
const assembly = @import("../asm.zig");
const keyboard_handle = @import("../drivers/keyboard.zig").handle;
const pic = @import("../drivers/pic.zig");
const std = @import("std");
const lapic = @import("../drivers/lapic.zig");

pub extern var interrupt_vector: [256]usize;

pub const Regs = packed struct {
    rax: u64,
    rcx: u64,
    rdx: u64,
    rbx: u64,
    rsp: u64,
    rbp: u64,
    rsi: u64,
    rdi: u64,
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
};

pub const Interrupt = packed struct {
    regs: Regs,
    interrupt: u64,
    code_err: u64,

    pub fn log(self: *const @This()) void {
        const expections_name = [_][]const u8{
            "Division by zero",
            "Debug",
            "Non-maskable Interrupt",
            "Breakpoint",
            "Overflow",
            "Bound range Exceeded",
            "Invalid Opcode",
            "Device not available",
            "Double fault",
            "0x9",
            "Invalid TSS",
            "Segment not present",
            "Stack-Segment Fault",
            "General Protection fault",
            "Page Fault",
            "Reversed",
            "x87 Floating-Point exception",
            "Alignment check",
            "Machine check",
            "SIMD Floating-Point Excepction",
            "Virtualization Exception",
            "Control Protection Exception",
            "Reserved",
            "Reserved",
            "Reserved",
            "Reserved",
            "Reserved",
            "Hypervisor injection exception",
            "VMM communcation exception",
            "Security exception",
            "Reserved",
        };

        std.debug.panic("Interrupt no: {x} name: {s}\nError code : {x}\n{any}", .{ self.interrupt, expections_name[self.interrupt], self.code_err, self.regs });
    }
};

pub fn irq_handler(interrupt: *const Interrupt) void {
    if (interrupt.interrupt == 33) {
        const value = @import("../asm.zig").inb(0x60);

        keyboard_handle(value);
        return;
    }
}

pub export fn interrupt_handler(rsp: u64) callconv(.C) u64 {
    const reg: *Interrupt = @ptrFromInt(rsp);

    if (reg.interrupt < 32) {
        reg.log();
    } else if (reg.interrupt <= 32 + 15) {
        irq_handler(reg);
    } else {
        serial.println("{}", .{reg.interrupt});
    }

    if (lapic.lapic) |_lapic| {
        _lapic.end_of_interrupt();
    }

    return rsp;
}
