const serial = @import("./serial.zig");

// zig fmt: off
var GDT: [5]GDTEntry = [_]GDTEntry{ 
    GDTEntry{}, 
    GDTEntry{ .access_byte = .{ .present = 1, .executable = 1, .read_write = 1, .typebit = TypeBit.CODE_DATA}, .flags = .{.granularity = true, .long = true}}, 
    GDTEntry{ .access_byte = .{ .present = 1, .read_write = 1, .typebit = TypeBit.CODE_DATA}, .flags = .{.granularity = true, .descriptor = 1}}, 
    GDTEntry{ .access_byte = .{ .present = 1, .read_write = 1, .typebit = TypeBit.CODE_DATA, .privilege = 3}, .flags = .{.granularity = true, .long = true}}, 
    GDTEntry{ .access_byte = .{ .present = 1, .executable = 1, .read_write = 1, .typebit = TypeBit.CODE_DATA, .privilege = 3}, .flags = .{.granularity = true, .descriptor = 1}}, 
};


const GDTPtr = packed struct {
    size: u16,
    address: u64,
};

const TypeBit = enum(u1) {
    SYSTEM = 0,
    CODE_DATA = 1,
};

const AccessByte = packed struct(u8) { 
    accessed_bit: u1 = 0,
    read_write: u1 = 0,
    dc: u1 = 0,
    executable : u1 = 0,
    typebit: TypeBit = TypeBit.SYSTEM,
    privilege: u2 = 0,
    present: u1 = 0,
};

pub const Flags = packed struct(u4) {
    reversed: u1 = 0,
    long: bool = false,
    descriptor: u1 = 0,
    granularity: bool = false,

    comptime {
        const std = @import("std");
        std.debug.assert(@as(u4, @bitCast(Flags{.granularity = true})) == 0b1000);
    }
};

pub const GDTEntry = packed struct(u64) {
    limit_low: u16 = 0x00,
    base_low: u16 = 0x00,
    base_middle: u8 = 0x00,
    access_byte: AccessByte = .{},
    limit_high: u4 = 0x00,
    flags : Flags = .{},
    base: u8 = 0x00,
};

extern fn load_gdt(gdt_descriptor: *const GDTPtr) void;

pub fn init() void {
    serial.print("Start GDT Init\n", .{});
    load_gdt(&GDTPtr{ .size = @as(u16, @sizeOf([5]GDTEntry) - 1), .address = @intFromPtr(&GDT) });
    serial.print("GDT ok\n", .{});
}
