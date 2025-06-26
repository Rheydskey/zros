const serial = @import("root").drivers.serial;
const keyboard_handle = @import("root").drivers.keyboard.handle;
const lapic = @import("root").drivers.lapic;
const scheduler = @import("root").scheduler;

pub extern var interrupt_vector: [256]usize;

pub const max_retry = 0;
pub var retry: u8 = 0;

pub const Regs = packed struct(u960) {
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rdi: u64,
    rsi: u64,
    rbp: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,
};

pub const Iret = packed struct(u320) {
    rip: u64,
    cs: u64,
    flags: u64,
    rsp: u64,
    ss: u64,

    pub inline fn debug(self: @This()) void {
        serial.println_nolock(
            \\ rip: {x}
            \\ cs: {x}
            \\ flags: {x}
            \\ rsp: {x}
            \\ ss: {x}
        , .{ self.rip, self.cs, self.flags, self.rsp, self.ss });
    }
};

pub const Context = packed struct(u1408) {
    regs: Regs,
    interrupt_no: u64,
    error_code: u64,
    iret: Iret,

    pub inline fn takeValueOf(self: *@This(), from: *const @This()) void {
        self.* = from.*;
    }
};

pub const Log = packed struct {
    const Stacktrace = packed struct {
        next: *Stacktrace,
        addr: u64,
    };

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

    pub fn log(ctx: *const Context) void {
        // Prevent loop
        if (retry > max_retry) {
            while (true)
                asm volatile ("hlt");
        }

        retry += 1;

        serial.println_nolock("===== GOT AN INTERRUPT =====", .{});
        // 0xE == PAGE_FAULT
        if (ctx.interrupt_no == 0xE) {
            var cr2: u64 = 0;

            cr2 = asm volatile ("mov  %%cr2, %[value]"
                : [value] "=r" (-> u64),
            );

            serial.println_nolock("FAULTY ADDR: 0x{X}", .{cr2});
        }

        serial.println_nolock("Interrupt no: {x} name: {s}\nError code : 0b{b}\n{any}", .{ ctx.interrupt_no, expections_name[ctx.interrupt_no], ctx.error_code, ctx.regs });
        write_stacktrace(ctx.regs.rbp);
    }

    pub fn write_stacktrace(rsp: u64) void {
        serial.println_nolock("Stacktrace:", .{});

        var rbp: *align(1) Stacktrace = @ptrFromInt(rsp);

        var i: u32 = 0;
        while (@intFromPtr(rbp) != 0x0) : (i += 1) {
            serial.println_nolock("{}: 0x{X}", .{ i, rbp.addr });
            rbp = rbp.next;
        }
    }
};

pub fn irq_handler(ctx: *Context) void {
    if (ctx.interrupt_no == 32) {
        scheduler.schedule(ctx) catch {
            @panic("Cannot schedule");
        };
        return;
    }

    if (ctx.interrupt_no == 33) {
        const value = @import("root").assembly.inb(0x60);

        keyboard_handle(value);
        return;
    }
}

pub export fn interrupt_handler(ctx: *Context) callconv(.C) u64 {
    if (ctx.interrupt_no < 32) {
        Log.log(ctx);
    } else if (ctx.interrupt_no <= 32 + 15) {
        irq_handler(ctx);
    } else {
        serial.println_nolock("UNHANDLED INTERRUPT: {x}", .{ctx.interrupt_no});
    }

    if (lapic.lapic) |_lapic| {
        _lapic.end_of_interrupt();
    }

    return @intFromPtr(ctx);
}
