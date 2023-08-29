const outb = @import("./asm.zig").outb;
const inb = @import("./asm.zig").inb;
const std = @import("std");

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
        var com: u16 = Com.COM1;

        try outb(com + 1, 0x00);
        try outb(com + 3, 0x80);
        try outb(com, 0x3);
        try outb(com + 1, 0);
        try outb(com + 3, 0x03);
        try outb(com + 2, 0xC7);
        try outb(com + 4, 0x0B);
        try outb(com + 4, 0x1E);
        try outb(com, 0xAE);

        if (try inb(com) != 0xAE) {
            return error.SerialFault;
        }

        try outb(com + 4, 0x0F);

        return Serial{};
    }

    pub fn is_transmit_empty() u8 {
        return inb(Com.COM1 + 5) catch {
            return 1;
        } & 0x20;
    }

    pub fn is_serial_receiving() bool {
        return inb(Com.COM1 + 5) catch {
            return false;
        } & 1 == 0;
    }

    pub fn read() !u8 {
        while (Serial.is_serial_receiving()) {}
        return inb(Com.COM1);
    }

    pub fn write(value: u8) !void {
        while (Serial.is_transmit_empty() == 0) {}
        try outb(Com.COM1, value);
    }

    pub fn write_array(values: []const u8) void {
        for (values) |value| {
            Serial.write(value) catch {};
        }
    }

    pub fn writeWithContext(self: Serial, values: []const u8) WriteError!usize {
        _ = self;
        Serial.write_array(values);

        return 0;
    }

    const WriteError = error{CannotWrite};

    const SerialWriter = std.io.Writer(Serial, WriteError, writeWithContext);
    pub fn writer() SerialWriter {
        return .{ .context = Serial{} };
    }
};
