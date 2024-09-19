const println = @import("./drivers/serial.zig").println;
const cpu = @import("./cpu.zig");
const limine_rq = @import("./limine_rq.zig");
const limine = @import("limine");

pub fn ap_handler(a: *limine.SmpInfo) callconv(.C) noreturn {
    println("Welcome from {}", .{a.processor_id});
    while (true) {}
}

pub fn init() !void {
    const running_cpu = cpu.get_id();
    const limine_smp = limine_rq.smp.response.?;

    for (limine_smp.cpus()) |entry| {
        if (entry.processor_id == running_cpu) {
            continue;
        }

        // println("CPU: {}", .{i});
        entry.goto_address = &ap_handler;
    }
}
