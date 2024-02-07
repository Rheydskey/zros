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
        serial.print("Error code : {x}", .{self.code_err});
    }
};

pub export fn interrupt_handler(rsp: u64) callconv(.C) u64 {
    serial.print("HERE", .{});
    const reg: *Interrupt = @ptrFromInt(rsp);
    reg.log();

    while (true) {}

    return rsp;
}

const InterruptStackFrame = struct {};

pub export fn keyboard(interrupt: *const InterruptStackFrame) callconv(.C) void {
    _ = interrupt;

    serial.print("Enter keyboard\n", .{});
    var scancode = assembly.inb(0x60);
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
