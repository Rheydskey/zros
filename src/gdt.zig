const serial = @import("./drivers/serial.zig");
const tss = @import("./tss.zig");

extern fn load_gdt(gdt_descriptor: *const GDTPtr) void;
extern fn load_tss() void;

var TSS: tss.TaskSegment = .{
    .rsp = .{
        .rsp0 = 0,
        .rsp1 = 0,
        .rsp2 = 0,
    },
    .ist = .{
        .ist1 = 0,
        .ist2 = 0,
        .ist3 = 0,
        .ist4 = 0,
        .ist5 = 0,
        .ist6 = 0,
        .ist7 = 0,
    },
    .iopb = .{
        .iopb = 0,
    },
};

const TssEntry = packed struct(u128) {
    length: u16,
    base_low: u16,
    base_mid_low: u8,
    flags: u16,
    base_mid_high: u8,
    base_high: u32,
    reserved: u32 = 0,

    pub fn fromAddr(ptr: usize) TssEntry {
        return .{
            .length = @sizeOf(tss.TaskSegment),
            .base_low = @intCast(ptr & 0xFFFF),
            .base_mid_low = @intCast(ptr >> 16 & 0xff),
            .flags = 0b1000_1001,
            .base_mid_high = @intCast(ptr >> 24 & 0xff),
            .base_high = @intCast(ptr >> 32),
        };
    }
};

const Gdt = extern struct {
    entries: [5]GDTEntry align(1),
    tss: TssEntry align(1) = undefined,
};

var GDT: Gdt = Gdt{ .entries = [_]GDTEntry{
    GDTEntry{},
    GDTEntry{
        .access_byte = .{ .present = true, .executable = true, .read_write = true, .typebit = TypeBit.CODE_DATA },
        .flags = .{ .granularity = true, .long = true },
    },
    GDTEntry{
        .access_byte = .{ .present = true, .read_write = true, .typebit = TypeBit.CODE_DATA },
        .flags = .{ .granularity = true, .descriptor = 1 },
    },
    GDTEntry{
        .access_byte = .{ .present = true, .read_write = true, .executable = true, .typebit = TypeBit.CODE_DATA, .privilege = 3 },
        .flags = .{ .granularity = true, .long = true },
    },
    GDTEntry{
        .access_byte = .{ .present = true, .read_write = true, .typebit = TypeBit.CODE_DATA, .privilege = 3 },
        .flags = .{ .granularity = true, .descriptor = 1 },
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

pub const Flags = packed struct(u4) {
    reversed: u1 = 0,
    long: bool = false,
    descriptor: u1 = 0,
    granularity: bool = false,
};

pub const GDTEntry = packed struct(u64) {
    limit_low: u16 = 0x00,
    base_low: u16 = 0x00,
    base_middle: u8 = 0x00,
    access_byte: AccessByte = .{},
    limit_high: u4 = 0x00,
    flags: Flags = .{},
    base: u8 = 0x00,
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
