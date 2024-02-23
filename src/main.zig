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

const Color = extern struct {
    blue: u8,
    green: u8,
    red: u8,
    alpha: u8 = 255,
};

export var base_revision: limine.BaseRevision = .{ .revision = 1 };
export var framebuffer: limine.FramebufferRequest = .{};
export var memory_map: limine.MemoryMapRequest = .{};
export var hhdm: limine.HhdmRequest = .{};

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

    serial.println("HHDM offset: {x}", .{hhdm.response.?.offset});
    gdt.init();
    try idt.init();

    if (framebuffer.response) |response| {
        if (response.framebuffer_count > 0) {
            const fb = response.framebuffers_ptr[0];
            const fb_addr = fb.address;

            serial.println("{*} is size of {}*{}", .{ fb_addr, fb.height, fb.width });
            var offset: u64 = 0;
            for (0..fb.height) |y| {
                for (0..fb.width) |x| {
                    const color: Color = .{
                        .blue = @truncate(x ^ y),
                        .red = @truncate((y * 2) ^ (x * 2)),
                        .green = @truncate((y * 4) ^ (x * 4)),
                    };

                    @as(*u32, @ptrCast(@alignCast(fb_addr + offset))).* = @bitCast(color);

                    offset += 4;
                }
            }
        }
    }

    if (memory_map.response) |response| {
        pmm.pmm_init(response, hhdm.response.?);
    }

    serial.println("Start init", .{});

    while (true) {
        const value = try serial.Serial.read();
        if (value == 0) continue;

        serial.print("{} => {}\n", .{ value, keyboard.event2enum(value) });
    }
}

export fn _start() void {
    main() catch {};
}
