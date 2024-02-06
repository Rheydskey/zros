const serial = @import("serial.zig");
const std = @import("std");
const interrupt = @import("idt/interrupt.zig");
const pic = @import("pic.zig");

const IDT_SIZE = 256;

var IDT: [IDT_SIZE]IDTEntry = [_]IDTEntry{IDTEntry{}} ** IDT_SIZE;

const IDTPtr = packed struct(u80) {
    size: u16,
    base_address: u64,
};

pub const IDTEntry = packed struct(u128) {
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

    pub const InterruptToHandler = *const fn () callconv(.Naked) void;
    pub const InterruptHandler = *const fn (interrupt: *const interrupt.InterruptStackFrame) callconv(.C) void;

    pub fn set_function(self: *IDTEntry, handler: InterruptToHandler) void {
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

pub fn init() !void {
    asm volatile ("cli");
    serial.print("Start IDT init\n", .{});

    try pic.load_pic();

    inline for (0..15) |i| {
        IDT[i].set_function(comptime interrupt.makeHandler(i));
    }

    inline for (16..21) |i| {
        IDT[i].set_function(comptime interrupt.makeHandler(i));
    }

    //    IDT[30].set_function(&interrupt.interrupt_handler);

    //  IDT[32].set_function(&interrupt.pit);
    // IDT[33].set_function(&interrupt.keyboard);

    var descriptor = &IDTPtr{ .size = @sizeOf([256]IDTEntry) - 1, .base_address = @intFromPtr(&IDT) };
    asm volatile ("lidt (%[idtr])"
        :
        : [idtr] "r" (&descriptor),
        : "memory"
    );

    asm volatile ("sti");

    serial.print("IDT ok", .{});
}
