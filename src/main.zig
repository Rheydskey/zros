const serial = @import("./serial.zig");
const gdt = @import("./gdt.zig");
const idt = @import("./idt.zig");
const assembly = @import("./asm.zig");
const keyboard = @import("keyboard.zig");
const builtin = @import("std").builtin;
const iter = @import("./iter.zig");
const limine = @import("limine");
const pmm = @import("./pmm.zig");
const utils = @import("./utils.zig");
const build_options = @import("build_options");
const vmm = @import("./vmm.zig");
const fb = @import("fbscreen.zig");
const limine_rq = @import("limine_rq.zig");
const acpi = @import("./acpi.zig");

pub fn screenfiller(x: u64, y: u64) fb.Color {
    return .{
        .blue = @truncate(x ^ y),
        .red = @truncate((y * 2) ^ (x * 2)),
        .green = @truncate((y * 4) ^ (x * 4)),
    };
}

const Stacktrace = struct {
    next: *Stacktrace,
    addr: u64,
};

// Only works in debug mode (TODO: Make this working in release mode)
pub fn stacktrace() void {
    if (build_options.release_mode) {
        serial.println("No stacktrace in release mode", .{});
        return;
    }

    serial.println("Stacktrace:", .{});

    var rbp: *Stacktrace = @ptrFromInt(@frameAddress());

    var i: u32 = 0;
    while (@intFromPtr(rbp.next) != 0x0) {
        serial.println("{}: 0x{X}", .{ i, rbp.addr });
        rbp = rbp.next;
        i += 1;
    }
}

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    serial.println(
        \\====== This is a panic message ======
        \\{s}
    , .{msg});
    stacktrace();

    while (true) {}
}

pub fn main() !noreturn {
    _ = serial.Serial.init() catch {
        asm volatile ("hlt");
        return error.CannotWrite;
    };

    gdt.init();
    idt.init();

    if (limine_rq.memory_map.response) |response| {
        try pmm.pmm_init(response, limine_rq.hhdm.response.?);
    }

    try vmm.init(limine_rq.hhdm.response.?);

    if (limine_rq.framebuffer.response) |response| {
        if (response.framebuffer_count > 0) {
            const framebuf = response.framebuffers_ptr[0];
            fb.fb_ptr = fb.Framebuffer.init(@intFromPtr(framebuf.address), framebuf.height, framebuf.width);
        }
    }

    try acpi.init();

    serial.println("{s}", .{acpi.rspd.?.signature});

    const apic = try acpi.rspt.?.get_apic();

    serial.println("{d}", .{apic.lapic_addr});

    try fb.fb_ptr.?.fillWith(screenfiller);

    while (true) {
        const value = try serial.Serial.read();
        if (value == 0) continue;

        serial.print("{} => {}\n", .{ value, keyboard.event2enum(value) });
    }
}

export fn _start() noreturn {
    main() catch |i| {
        serial.println("{}", .{i});
    };
    while (true) {}
}
