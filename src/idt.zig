const serial = @import("serial.zig");
const std = @import("std");
const interrupt = @import("idt/interrupt.zig");
const pic = @import("pic.zig");

const IDT_SIZE = 256;

extern fn idt_load(u64) void;

var idt: Idt = Idt.empty();

const Idt = struct {
    entries: [IDT_SIZE]IdtEntry,

    fn empty() @This() {
        return @This(){ .entries = [_]IdtEntry{IdtEntry.empty()} ** IDT_SIZE };
    }
};

const IdtPtr = packed struct(u80) {
    size: u16,
    base_address: u64,
};

pub const IdtEntry = packed struct(u128) {
    offset_l: u16 = 0,
    code_segment: u16 = 0,
    ist: u8 = 0,
    type_attr: EntryAttributes = .{},
    offset_m: u16 = 0,
    offset_h: u32 = 0,
    zero: u32 = 0,

    pub fn set_offset(self: *@This(), base: u64) void {
        self.*.offset_l = @truncate(base);
        self.*.offset_m = @truncate(base >> 16);
        self.*.offset_h = @truncate(base >> 32);
    }

    pub const InterruptHandler = *const fn (interrupt: *const interrupt.Regs) callconv(.C) void;

    pub fn empty() @This() {
        return @This(){};
    }

    pub fn new(handler: u64, ist: Ist, idt_flags: GateType) @This() {
        var self = IdtEntry{};
        self.ist = @intFromEnum(ist);
        self.type_attr = EntryAttributes{ .gate_type = idt_flags, .present = true };

        self.set_function(handler);

        return self;
    }

    pub fn set_function(self: *@This(), handler: u64) void {
        self.*.type_attr = .{ .present = true };

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

    const Ist = enum(u8) { Unused = 0 };
};

pub fn init() !void {
    asm volatile ("cli");
    serial.print("Start IDT init\n", .{});

    //    try pic.load_pic();

    inline for (0..256) |i| {
        idt.entries[i] = IdtEntry.new(interrupt.interrupt_vector[i], IdtEntry.Ist.Unused, IdtEntry.GateType.Interrupt);
    }

    //    IDT[30].set_function(&interrupt.interrupt_handler);

    //  IDT[32].set_function(&interrupt.pit);
    // IDT[33].set_function(&interrupt.keyboard);

    var descriptor = &IdtPtr{ .size = @sizeOf([256]IdtEntry) - 1, .base_address = @intFromPtr(&idt) };

    idt_load(@intFromPtr(&descriptor));

    asm volatile ("sti");

    serial.print("IDT ok", .{});
}
