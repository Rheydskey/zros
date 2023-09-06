const serial = @import("../serial.zig");
const assembly = @import("../asm.zig");
const keyboard_handle = @import("../keyboard.zig").handle;
const pic = @import("../pic.zig");

pub const register_64 = extern struct {
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rsi: u64,
    rdi: u64,
    rbp: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,

    pub inline fn logit(self: *const volatile @This()) void {
        serial.print(
            \\ STACK FRAME
            \\ r15: {x}
            \\ r14: {x}
            \\ r13: {x}
            \\ r12: {x}
            \\ r11: {x}
            \\ r10: {x}
            \\ r9: {x}
            \\ r8: {x}
            \\ rsi: {x}
            \\ rdi: {x}
            \\ rbp: {x}
            \\ rdx: {x}
            \\ rcx: {x}
            \\ rbx: {x}
            \\ rax: {x}
        , .{ self.r15, self.r14, self.r13, self.r12, self.r11, self.r10, self.r9, self.r8, self.rsi, self.rdi, self.rbp, self.rdx, self.rcx, self.rbx, self.rax });
    }
};

pub const InterruptStackFrame = extern struct {
    register: register_64,
};

pub export fn interrupt_handler(interrupt: *const volatile InterruptStackFrame) callconv(.C) void {
    _ = interrupt;
    _ = serial.Serial.write_array("== Interrupt handler ==\n");
    // interrupt.register.logit();
}

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
