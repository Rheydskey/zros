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

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    serial.println("{s}", .{msg});
    // serial.println("{s}", stacktrace.?.instruction_addresses);
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
