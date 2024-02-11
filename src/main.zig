const serial = @import("./serial.zig");
const gdt = @import("./gdt.zig");
const idt = @import("./idt.zig");
const assembly = @import("./asm.zig");
const keyboard = @import("keyboard.zig");
const builtin = @import("std").builtin;
const iter = @import("./iter.zig");
const pmm = @import("./pmm.zig");

pub fn panic(_: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    while (true) {}
}

pub fn main() !noreturn {
    _ = serial.Serial.init() catch {
        asm volatile ("hlt");
        return error.CannotWrite;
    };

    asm volatile ("cli");
    serial.println("Start init", .{});

    var a: pmm.BitMapU8 = pmm.BitMapU8.new();

    a.init();

    a.set(1);
    a.set(2);
    a.set(8);
    a.set(81);
    a.unset(2);
    serial.println("{}", .{a.get(1)});
    serial.println("{}", .{a.get(0)});
    a.debug();

    gdt.init();
    try idt.init();

    while (true) {
        const value = try serial.Serial.read();
        if (value == 0) continue;

        serial.print("{} => {}\n", .{ value, keyboard.event2enum(value) });
    }
}

export fn _start() void {
    main() catch {};
}
