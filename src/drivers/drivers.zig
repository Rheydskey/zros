pub const acpi = @import("../acpi//acpi.zig");
pub const ps2 = @import("./ps2.zig");
pub const serial = @import("serial.zig");
pub const fb = @import("fbscreen.zig");
pub const keyboard = @import("keyboard.zig");
pub const lapic = @import("lapic.zig");

pub fn init() !void {
    try acpi.init();

    try ps2.init();
}
