const limine = @import("limine");

pub const Color = extern struct {
    blue: u8,
    green: u8,
    red: u8,
    alpha: u8 = 255,
};

pub const Framebuffer = struct {
    height: u64,
    width: u64,
    ptr: [*]u32,
    cursor: u64,

    pub fn init(ptr: u64, height: u64, width: u64) @This() {
        return .{ .ptr = @ptrFromInt(ptr), .height = height, .width = width, .cursor = 0 };
    }

    pub fn write(self: *@This(), color: Color) void {
        self.writeAt(color, self.cursor);

        self.cursor += 1;
    }

    pub fn writeAt(
        self: *const @This(),
        color: Color,
        offset: u64,
    ) void {
        self.ptr[offset] = @bitCast(color);
    }

    pub fn fillWith(self: *@This(), fill: fn (x: u64, y: u64) Color) !void {
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                self.write(fill(x, y));
            }
        }
    }
};

pub var fb_ptr: ?Framebuffer = undefined;
