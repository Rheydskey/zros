const idt = @import("../idt.zig");
const serial = @import("../serial.zig");
const assembly = @import("../asm.zig");
const keyboard_handle = @import("../keyboard.zig").handle;
const pic = @import("../pic.zig");

extern var interrupt_vector: [256]usize;

pub const Regs = packed struct {
    rip: u64,
    rsp: u64,
    cr2: u64,
    cr3: u64,
    cs: u64,
    ss: u64,
    rflags: u64,
};

pub const Interrupt = packed struct {
    regs: Regs,
    interrupt: u64,
    code_err: u64,

    pub fn log(self: *const @This()) void {
        serial.print("Error code : {x}", self.code_err);
    }
};

fn interrupt_handler(rsp: u64) u64 {
    const reg: Interrupt = @ptrFromInt(rsp);
    reg.log();

    return rsp;
}

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
    vector: u64,
    error_code: u64,
    rip: u64,
    cs: u64,

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
            \\ vector: {x}
            \\ error_code: {x}
            \\ rip: {x}
            \\ cs: {x}
        , .{ self.r15, self.r14, self.r13, self.r12, self.r11, self.r10, self.r9, self.r8, self.rsi, self.rdi, self.rbp, self.rdx, self.rcx, self.rbx, self.rax, self.vector, self.error_code, self.rip, self.cs });
    }
};

pub const InterruptStackFrame = extern struct {
    register: register_64,
};

// https://github.com/48cf/zigux/blob/master/kernel/src/interrupts.zig
export fn interruptCommonHandler() callconv(.Naked) void {
    asm volatile (
        \\push %%rax
        \\push %%rbx
        \\push %%rcx
        \\push %%rdx
        \\push %%rbp
        \\push %%rdi
        \\push %%rsi
        \\push %%r8
        \\push %%r9
        \\push %%r10
        \\push %%r11
        \\push %%r12
        \\push %%r13
        \\push %%r14
        \\push %%r15
        \\xor %%rax, %%rax
        \\mov %%ds, %%ax
        \\push %%rax
        \\mov %%es, %%ax
        \\push %%rax
        \\
        \\mov %%rsp, %%rdi
        \\call swapGsIfNeeded
        \\mov %%rsp, %%rdi
        \\call interrupt_handler
        \\mov %%rsp, %%rdi
        \\call swapGsIfNeeded
        \\
        \\pop %%rax
        \\mov %%ax, %%es
        \\pop %%rax
        \\mov %%ax, %%ds
        \\pop %%r15
        \\pop %%r14
        \\pop %%r13
        \\pop %%r12
        \\pop %%r11
        \\pop %%r10
        \\pop %%r9
        \\pop %%r8
        \\pop %%rsi
        \\pop %%rdi
        \\pop %%rbp
        \\pop %%rdx
        \\pop %%rcx
        \\pop %%rbx
        \\pop %%rax
        \\
        \\add $16, %%rsp
        \\iretq
    );
}

pub fn makeHandler(comptime error_vector: usize) idt.IDTEntry.InterruptToHandler {
    var a = struct {
        fn handler() callconv(.Naked) void {
            const has_error_code = switch (error_vector) {
                0x8 => true,
                0xA...0xE => true,
                0x11 => true,
                0x15 => true,
                0x1D...0x1E => true,
                else => false,
            };

            if (comptime (has_error_code)) {
                asm volatile (
                    \\pushq %[vector]
                    \\jmp interruptCommonHandler
                    :
                    : [vector] "i" (error_vector),
                );
            } else {
                asm volatile (
                    \\pushq $0
                    \\pushq %[vector]
                    \\jmp interruptCommonHandler
                    :
                    : [vector] "i" (error_vector),
                );
            }
        }
    };

    return a.handler;
}

export fn swapGsIfNeeded(frame: *InterruptStackFrame) callconv(.C) void {
    if (frame.register.cs != 0x28) {
        asm volatile ("swapgs");
    }
}

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
