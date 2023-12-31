comptime {
    @setRuntimeSafety(false);
}

const serial = @import("./serial.zig");
const gdt = @import("./gdt.zig");
const idt = @import("./idt.zig");
const assembly = @import("./asm.zig");
const keyboard = @import("keyboard.zig");
const builtin = @import("std").builtin;

pub fn panic(_: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    while (true) {}
}

pub fn main() !noreturn {
    _ = serial.Serial.init() catch {
        asm volatile ("hlt");
        return error.CannotWrite;
    };

    asm volatile ("cli");
    _ = serial.print("Start init", .{});

    gdt.init();
    try idt.init();

    // asm volatile ("int $0x00");

    while (true) {
        var value = try serial.Serial.read();
        if (value == 0) continue;

        serial.print("{} => {}\n", .{ value, keyboard.event2enum(value) });
    }
}

export fn _start() void {
    main() catch {};
}
