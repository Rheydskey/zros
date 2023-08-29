const serial = @import("serial.zig");
const std = @import("std");

var IDT: [256]IDTEntry = [_]IDTEntry{IDTEntry{}} ** 256;

const IDTPtr = packed struct {
    size: u16,
    base_address: u64,
};

const IDTFlags = struct {
    const Present = 1 << 7;
    const Ring0 = 0 << 5;
    const Ring1 = 1 << 5;
    const Ring2 = 1 << 5;
    const Ring3 = 3 << 5;
    const SS = 1 << 4;
    const Interrupt = 0xE;
    const Trap = 0xF;
};

const InterruptStackFrame = extern struct {
    instruction_pointer: u64,
    code_segment: u64,
    cpu_flags: u64,
    stack_point: u64,
    stack_segment: u64,
};
const InterruptHandler = fn () callconv(.Naked) void;
const IDTEntry = packed struct {
    offset_l: u16 = 0,
    code_segment: u16 = 0,
    ist: u8 = 0,
    type_attr: u8 = 0,
    offset_m: u16 = 0,
    offset_h: u32 = 0,
    zero: u32 = 0,

    pub fn set_offset(self: *IDTEntry, base: usize) void {
        self.*.offset_l = @intCast(@as(u16, @truncate(base)));

        self.*.offset_m = @intCast(@as(u16, @truncate(base >> 16)));
        serial.Serial.write_array("No overflow >> 16");

        self.*.offset_h = @intCast(@as(u16, @truncate(base >> 32)));
        serial.Serial.write_array("No overflow >> 32");
    }

    pub fn set_function(self: *IDTEntry, comptime handler: InterruptHandler) void {
        serial.Serial.write_array("try type attribute\n");
        self.*.type_attr = IDTFlags.Present | IDTFlags.Ring0 | IDTFlags.Interrupt;
        serial.Serial.write_array("Wrote type attribute\n");
        var teststr = serial.Serial.writer();
        teststr.print("{d}", .{@intFromPtr(handler)}) catch {};

        const ptrusize: usize =
            @intFromPtr(handler);
        _ = ptrusize;
        serial.Serial.write_array("Wrote offset\n");
        self.*.code_segment = 8;
        serial.Serial.write_array("Wrote segment");
    }
};

extern fn load_idt(idt: *const IDTPtr) void;

pub fn init() !void {
    asm volatile ("cli");
    serial.Serial.write_array("Start IDT init\n");

    IDT[0].set_function(divise_by_zero);

    serial.Serial.write_array("Division setted\n");

    serial.Serial.write_array("Handler setted");

    load_idt(&IDTPtr{ .size = @sizeOf([256]IDTEntry) - 1, .base_address = @intFromPtr(&IDT) });
    asm volatile ("sti");
}

pub export fn divise_by_zero(interrupt: usize) callconv(.Interrupt) void {
    _ = interrupt;
    serial.Serial.write_array("divise by zero");
    asm volatile ("hlt");
}

pub export fn debug(interrupt: *InterruptStackFrame) callconv(.Interrupt) void {
    serial.Serial.write_array("debug");
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
