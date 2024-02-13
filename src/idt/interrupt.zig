const idt = @import("../idt.zig");
const serial = @import("../serial.zig");
const assembly = @import("../asm.zig");
const keyboard_handle = @import("../keyboard.zig").handle;
const pic = @import("../pic.zig");

pub extern var interrupt_vector: [256]usize;

pub const Regs = packed struct {
    rbp: u64,
    rsp: u64,
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

        if (self.interrupt < 31) {
            serial.print("Interrupt no: {x} name: {s}\nError code : {x}\n", .{ self.interrupt, expections_name[self.interrupt], self.code_err });
            return;
        }

        serial.print("Interrupt no: {x}\nError code : {x}\n", .{ self.interrupt, self.code_err });
    }
};

pub export fn interrupt_handler(rsp: u64) callconv(.C) u64 {
    const reg: *Interrupt = @ptrFromInt(rsp);
    reg.log();

    while (true) {}

    return rsp;
}

const InterruptStackFrame = struct {};

pub export fn keyboard(interrupt: *const InterruptStackFrame) callconv(.C) void {
    _ = interrupt;

    serial.print("Enter keyboard\n", .{});
    const scancode = assembly.inb(0x60);
    // catch {
    //    serial.print("Cannot read (keyboard)", .{});
    //    return;
    //};

    keyboard_handle(scancode);
    pic.end_of_pic1();

    asm volatile ("sti");
}

pub export fn pit(interrupt: *const InterruptStackFrame) callconv(.C) void {
    _ = interrupt;
    return;
}
