const outb = @import("../asm.zig").outb;
const inb = @import("../asm.zig").inb;
const std = @import("std");
const sync = @import("../sync.zig");

var serial_writer = sync.TicketLock(Serial.SerialWriter).init(Serial.writer());

pub fn print_err(comptime format: []const u8, args: anytype) void {
    print("[ERR] " ++ format ++ "\n", args);
}

pub fn print_ok(comptime format: []const u8, args: anytype) void {
    print("[OK] " ++ format ++ "\n", args);
}

pub fn print(comptime format: []const u8, args: anytype) void {
    _ = Serial.writer().print(format, args) catch {};
}

pub fn println(comptime format: []const u8, args: anytype) void {
    const writer = serial_writer.lock();
    defer serial_writer.unlock();

    _ = writer.print(format ++ "\n", args) catch {};
}

pub const WriteOption = struct { linenumber: bool = false };

pub const Com = struct {
    const COM1 = 0x3F8;
    const COM2 = 0x2F8;
    const COM3 = 0x3E8;
    const COM4 = 0x2E8;
    const COM5 = 0x5F8;
    const COM6 = 0x4F8;
    const COM7 = 0x5E8;
    const COM8 = 0x4E8;
};

pub const Serial = struct {
    pub fn init() !Serial {
        const com: u16 = Com.COM1;

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

    pub fn is_transmit_empty() u8 {
        return inb(Com.COM1 + 5) & 0x20;
    }

    pub fn is_serial_receiving() u8 {
        return inb(Com.COM1 + 5) & 1;
    }

    pub fn read() !u8 {
        while (Serial.is_serial_receiving() == 0) {}
        return inb(Com.COM1);
    }

    pub fn write(value: u8) void {
        while (Serial.is_transmit_empty() == 0) {}
        outb(Com.COM1, value);
    }

    pub fn write_array(values: []const u8) usize {
        var written: usize = 0;
        for (values) |value| {
            written += 1;
            Serial.write(value);
        }

        return written;
    }

    pub fn writeWithContext(self: Serial, values: []const u8) WriteError!usize {
        _ = self;
        return Serial.write_array(values);
    }

    const WriteError = error{CannotWrite};

    const SerialWriter = std.io.Writer(Serial, WriteError, writeWithContext);
    pub fn writer() SerialWriter {
        return .{ .context = Serial{} };
    }
};
