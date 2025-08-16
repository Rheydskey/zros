const outb = @import("../asm.zig").outb;
const inb = @import("../asm.zig").inb;
const std = @import("std");
const sync = @import("../sync.zig");
const Io = @import("std").io;

var serial_writer = sync.TicketLock(SerialWriter).init(SerialWriter.init(Com.COM1));

pub const Com = enum(u16) {
    COM1 = 0x3F8,
    COM2 = 0x2F8,
    COM3 = 0x3E8,
    COM4 = 0x2E8,
    COM5 = 0x5F8,
    COM6 = 0x4F8,
    COM7 = 0x5E8,
    COM8 = 0x4E8,
};

pub const Serial = struct {
    pub fn init() !Serial {
        const com: u16 = @intFromEnum(Com.COM1);

        outb(com + 1, 0x00);
        outb(com + 3, 0x80);
        outb(com, 0x03);
        outb(com + 1, 0);
        outb(com + 3, 0x03);
        outb(com + 2, 0xC7);
        outb(com + 4, 0x0B);
        outb(com + 4, 0x1E);
        outb(com, 0xAE);

        if (inb(com) != 0xAE) {
            return error.SerialFault;
        }

        outb(com + 4, 0x0F);

        return Serial{};
    }

    pub fn is_serial_receiving() u8 {
        return inb(Com.COM1 + 5) & 1;
    }

    pub fn read() !u8 {
        while (Serial.is_serial_receiving() == 0) {}
        return inb(Com.COM1);
    }
};

const SerialWriter = struct {
    interface: Io.Writer,
    com: Com,

    pub fn is_transmit_empty(self: *SerialWriter) u8 {
        return inb(@intFromEnum(self.com) + 5) & 0x20;
    }

    pub fn drain(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const w: *SerialWriter = @alignCast(@fieldParentPtr("interface", io_w));
        var written: usize = data[data.len - 1].len * splat;
        while (w.is_transmit_empty() == 0) {}
        for (data[0 .. data.len - 1]) |chunck| {
            for (chunck) |byte| {
                outb(@intFromEnum(w.com), byte);
            }
            written += chunck.len;
        }

        for (0..splat) |_| {
            for (data[data.len - 1]) |chunck| {
                outb(@intFromEnum(w.com), chunck);
            }
        }
        io_w.end = 0;
        return written;
    }

    pub fn init(com: Com) SerialWriter {
        return .{ .interface = .{
            .vtable = &.{
                .drain = drain,
            },
            .buffer = &[_]u8{},
        }, .com = com };
    }
};

pub fn print_err(comptime format: []const u8, args: anytype) void {
    print("[ERR] " ++ format ++ "\n", args);
}

pub fn print_ok(comptime format: []const u8, args: anytype) void {
    print("[OK] " ++ format ++ "\n", args);
}

pub fn print(comptime format: []const u8, args: anytype) void {
    if (@import("builtin").is_test) {
        @import("std").debug.print(format, args);
        return;
    }

    const writer = serial_writer.lock();
    defer serial_writer.unlock();
    writer.interface.print(format, args) catch {};
}

pub fn println_nolock(comptime format: []const u8, args: anytype) void {
    serial_writer.value.interface.print(format ++ "\n", args) catch {};
}

pub fn println(comptime format: []const u8, args: anytype) void {
    print(format ++ "\n", args);
}
