const serial = @import("./serial.zig");

// zig fmt: off
var GDT: [6]GDTEntry = [_]GDTEntry{ 
    GDTEntry{}, 
    GDTEntry{ .flag = GDTEntryFlags.SEGMENT | GDTEntryFlags.PRESENT | GDTEntryFlags.READWRITE | GDTEntryFlags.EXECUTABLE, .granularity = GDTEntry.GRANULARITY }, 
    GDTEntry{ .flag = GDTEntryFlags.SEGMENT | GDTEntryFlags.PRESENT | GDTEntryFlags.READWRITE }, 
    GDTEntry{ .flag = GDTEntryFlags.SEGMENT | GDTEntryFlags.PRESENT | GDTEntryFlags.READWRITE | GDTEntryFlags.USER, }, 
    GDTEntry{ .flag = GDTEntryFlags.SEGMENT | GDTEntryFlags.PRESENT | GDTEntryFlags.READWRITE | GDTEntryFlags.EXECUTABLE | GDTEntryFlags.USER, .granularity = GDTEntry.GRANULARITY}, 
    GDTEntry{} 
};

const GDTPtr = packed struct {
    size: u16,
    address: u64,
};

pub const GDTEntry = packed struct {
    const GRANULARITY = 0b0010;
    
    limit_low: u16 = 0x00,
    base_low: u16 = 0x00,
    base_middle: u8 = 0x00,
    flag: u8 = 0x00,
    limit_high: u4 = 0x00,
    granularity: u4 = 0x00,
    base: u8 = 0x00,


};

pub const GDTEntryFlags = struct {
    const SEGMENT = 0b00010000;
    const PRESENT = 0b10000000;
    const USER = 0b11000000;
    const EXECUTABLE = 0b00001000;
    const READWRITE = 0b00000010;
};

extern fn load_gdt(gdt_descriptor: *const GDTPtr) void;

test "size of gdtentry" {
    const std = @import("std");
    std.log.warn("{}", .{@sizeOf(GDT)});
    try std.testing.expect(@sizeOf(GDTEntry) * 8 == 64);
}

pub fn init() void {
    serial.print("Start GDT Init\n", .{});
    load_gdt(&GDTPtr{ .size = @as(u16, @sizeOf([6]GDTEntry) - 1), .address = @intFromPtr(&GDT) });
    serial.print("GDT ok\n", .{});
}
