const serial = @import("serial.zig");
const std = @import("std");

var IDT: [256]IDTEntry = [_]IDTEntry{IDTEntry{}} ** 256;

const IDTPtr = packed struct(u80) {
    size: u16,
    base_address: u64,
};

const InterruptStackFrame = extern struct {
    instruction_pointer: u64,
    code_segment: u64,
    cpu_flags: u64,
    stack_point: u64,
    stack_segment: u64,
};

const IDTEntry = packed struct(u128) {
    offset_l: u16 = 0,
    code_segment: u16 = 0,
    ist: u8 = 0,
    type_attr: EntryAttributes = .{},
    offset_m: u16 = 0,
    offset_h: u32 = 0,
    zero: u32 = 0,

    pub fn set_offset(self: *IDTEntry, base: u64) void {
        self.*.offset_l = @truncate(base);
        self.*.offset_m = @truncate(base >> 16);
        self.*.offset_h = @truncate(base >> 32);
    }

    const InterruptHandler = fn (interrupt: *InterruptStackFrame) callconv(.C) void;

    pub fn set_function(self: *IDTEntry, handler: *const InterruptHandler) void {
        self.*.type_attr = .{ .present = true };

        self.set_offset(@intFromPtr(handler));

        self.*.code_segment = 8;
    }

    const GateType = enum(u4) { Interrupt = 0xE, Trap = 0xF };

    const EntryAttributes = packed struct(u8) {
        gate_type: GateType = .Interrupt,
        _reserved: u1 = 0,
        privilege: u2 = 0,
        present: bool = false,
    };
};

extern fn load_idt(idt: *const IDTPtr) void;

pub fn init() !void {
    asm volatile ("cli");
    serial.print("Start IDT init\n", .{});

    for (0..14) |i| {
        IDT[i].set_function(&divise_by_zero);
    }

    load_idt(&IDTPtr{ .size = @sizeOf([256]IDTEntry) - 1, .base_address = @intFromPtr(&IDT) });

    asm volatile ("sti");

    serial.print("IDT ok", .{});
}

pub export fn divise_by_zero(interrupt: *InterruptStackFrame) void {
    _ = interrupt;
    _ = serial.Serial.write_array("\ndivise_by_zero\n");
    asm volatile ("hlt");
}

pub export fn debug(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    serial.print("debug", .{});
    _ = interrupt;
}

pub fn non_maskable(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}

pub fn breakpoint(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}

pub fn overflow(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}
pub fn bound_range(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}
pub fn invalid_opcode(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}
pub fn device_not_available(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}
pub fn double_fault(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}
pub fn invalid_tss(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}
pub fn segment_not_present(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}
pub fn stack_segment(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}
pub fn protection(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}
pub fn fpu_fault(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}
pub fn alignment_check(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}

pub fn machine_check(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}
pub fn simd(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}
pub fn virtualization(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}

pub fn security(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}

pub fn page_fault(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    _ = interrupt;
}
