const serial = @import("./drivers/serial.zig");
const gdt = @import("./gdt.zig");
const idt = @import("./idt.zig");
const builtin = @import("std").builtin;
const limine = @import("limine");
const pmm = @import("./mem/pmm.zig");
const build_options = @import("build_options");
const vmm = @import("./mem/vmm.zig");
const fb = @import("./drivers/fbscreen.zig");
const limine_rq = @import("limine_rq.zig");
const acpi = @import("./acpi/acpi.zig");
const ps2 = @import("./drivers/ps2.zig");
const psf = @import("./psf.zig");

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
            serial.println("{any}", .{framebuf});

            const a: *align(1) const psf.Psf2 = @ptrCast(psf.lucida);
            fb.fb_ptr = fb.Framebuffer.init(@intFromPtr(framebuf.address), framebuf.height, framebuf.width, framebuf.pitch, framebuf.bpp, a);
        }
    }

    try acpi.init();

    try ps2.init();

    fb.fb_ptr.?.print_str("ZROS - 0.0.1+" ++ build_options.git_version, 0, 0);
    fb.fb_ptr.?.print_str("Hewwo worwd", 0, 16);
    while (true) {
        asm volatile ("hlt");
    }
}

export fn _start() noreturn {
    main() catch |i| {
        serial.println("{}", .{i});
    };
    while (true) {
        asm volatile ("hlt");
    }
}
