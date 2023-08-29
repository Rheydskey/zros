const serial = @import("./serial.zig");
const gdt = @import("./gdt.zig");
const idt = @import("./idt.zig");
const assembly = @import("./asm.zig");

pub fn main() !void {
    _ = serial.Serial.init() catch {
        asm volatile ("hlt");
        return;
    };
    asm volatile ("cli");
    serial.Serial.write_array("Start init");

    gdt.init();
    try idt.init();

    asm volatile ("hlt");
    while (true) {}
}

export fn _start() void {
    main() catch {};
}
