const serial = @import("serial.zig");
const std = @import("std");
const interrupt = @import("idt/interrupt.zig");
const pic = @import("pic.zig");

const IDT_SIZE = 256;

extern fn idt_load(usize) void;

var idt: Idt = undefined;

const Idt = struct {
    entries: [IDT_SIZE]IdtEntry,

    fn empty() @This() {
        return @This(){ .entries = [_]IdtEntry{undefined} ** IDT_SIZE };
    }
};

const IdtPtr = packed struct(u80) {
    size: u16,
    base_address: u64,
};

pub const IdtEntry = packed struct(u128) {
    offset_l: u16 = 0,
    code_segment: u16 = 8,
    ist: u8 = 0,
    type_attr: u8,
    offset_m: u16 = 0,
    offset_h: u32 = 0,
    zero: u32 = 0,

    pub fn set_offset(self: *@This(), base: u64) void {
        self.*.offset_l = @truncate(base);
        self.*.offset_m = @truncate(base >> 16);
        self.*.offset_h = @truncate(base >> 32);
    }

    pub const InterruptHandler = *const fn (interrupt: *const interrupt.Regs) callconv(.C) void;

    pub fn new(handler: u64, flags: u8) @This() {
        var self = IdtEntry{ .type_attr = flags };

        self.set_function(handler);

        return self;
    }

    pub fn set_function(self: *@This(), handler: u64) void {
        self.set_offset(handler);

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

pub fn init() !void {
    asm volatile ("cli");
    serial.print("Start IDT init\n", .{});

    inline for (0..31) |i| {
        idt.entries[i] = IdtEntry.new(interrupt.interrupt_vector[i], 0x8F); // 0x8E = Interrupt Gate
    }

    inline for (31..256) |i| {
        idt.entries[i] = IdtEntry.new(interrupt.interrupt_vector[i], 0x8E); // 0x8E = Interrupt Gate
    }

    var idtptr = IdtPtr{ .size = @sizeOf(Idt) - 1, .base_address = @intFromPtr(&idt) };

    idt_load(@intFromPtr(&idtptr));

    asm volatile ("sti");

    serial.print_ok("IDT", .{});
}
