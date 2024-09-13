const acpi = @import("../acpi//acpi.zig");
const ps2 = @import("./ps2.zig");

pub fn init() !void {
    try acpi.init();

    try ps2.init();
}
