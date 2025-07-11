const serial = @import("root").drivers.serial;
const tss = @import("./tss.zig");
const zeroes = @import("std").mem.zeroes;

extern fn load_gdt(gdt_descriptor: *const GDTPtr) void;
extern fn load_tss() void;

var TSS: tss.TaskSegment = zeroes(tss.TaskSegment);

const TssEntry = packed struct(u128) {
    length: u16,
    base_low: u16,
    base_mid_low: u8,
    flags: u16,
    base_mid_high: u8,
    base_high: u32,
    reserved: u32 = 0,

    const TssFlags = struct {
        const PRESENT = (1 << 7);
        const LONGMODE = (0x9);
    };

    pub fn fromAddr(ptr: usize) TssEntry {
        return .{
            .length = @sizeOf(tss.TaskSegment),
            .base_low = @intCast(ptr & 0xFFFF),
            .base_mid_low = @intCast((ptr >> 16) & 0xff),
            .flags = TssFlags.PRESENT | TssFlags.LONGMODE,
            .base_mid_high = @intCast((ptr >> 24) & 0xff),
            .base_high = @intCast(ptr >> 32),
        };
    }
};

const Gdt = extern struct {
    entries: [5]GDTEntry align(1),
    tss: TssEntry align(1) = zeroes(TssEntry),
};

var GDT: Gdt = Gdt{ .entries = [_]GDTEntry{
    zeroes(GDTEntry),
    GDTEntry{
        .access_byte = .{
            .present = true,
            .executable = true,
            .read_write = true,
            .typebit = TypeBit.CODE_DATA,
        },
        .flags = .{
            .granularity = true,
            .long = true,
        },
    },
    GDTEntry{
        .access_byte = .{
            .present = true,
            .read_write = true,
            .typebit = TypeBit.CODE_DATA,
        },
        .flags = .{
            .granularity = true,
            .descriptor = 1,
        },
    },
    GDTEntry{
        .access_byte = .{
            .present = true,
            .read_write = true,
            .executable = true,
            .typebit = TypeBit.CODE_DATA,
            .privilege = 3,
        },
        .flags = .{
            .granularity = true,
            .long = true,
        },
    },
    GDTEntry{
        .access_byte = .{
            .present = true,
            .read_write = true,
            .typebit = TypeBit.CODE_DATA,
            .privilege = 3,
        },
        .flags = .{
            .granularity = true,
            .descriptor = 1,
        },
    },
} };

const GDTPtr = packed struct {
    size: u16,
    address: u64,
};

const TypeBit = enum(u1) {
    SYSTEM = 0,
    CODE_DATA = 1,
};

const AccessByte = packed struct(u8) {
    accessed_bit: bool = false,
    read_write: bool = false,
    dc: bool = false,
    executable: bool = false,
    typebit: TypeBit = TypeBit.SYSTEM,
    privilege: u2 = 0,
    present: bool = false,
};

// https://osdev.wiki/wiki/Global_Descriptor_Table#Segment_Descriptor
pub const Flags = packed struct(u4) {
    const Descriptor = struct {
        const protected_16bit = 0;
        const protected_32bit = 1;
    };
    reserved: u1 = 0,
    long: bool = false,
    descriptor: u1 = Descriptor.protected_16bit,
    granularity: bool = false,
};

pub const GDTEntry = packed struct(u64) {
    limit_low: u16 = 0,
    base_low: u16 = 0,
    base_middle: u8 = 0,
    access_byte: AccessByte = .{},
    limit_high: u4 = 0,
    flags: Flags = .{},
    base: u8 = 0,
};

pub fn tss_init(kernel_stack: u64) void {
    TSS.rsp.rsp0 = kernel_stack;
}

pub fn init() void {
    serial.print("Start GDT Init\n", .{});

    GDT.tss = TssEntry.fromAddr(@intFromPtr(&TSS));
    load_gdt(&GDTPtr{ .size = @sizeOf(Gdt), .address = @intFromPtr(&GDT) });
    load_tss();

    serial.print_ok("GDT", .{});
}
