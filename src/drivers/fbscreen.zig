const limine = @import("limine");
const psf2 = @import("../psf.zig");

pub const Color = extern struct {
    blue: u8,
    green: u8,
    red: u8,
    alpha: u8 = 255,

    const BLACK: Color = .{ .blue = 0, .green = 0, .red = 0 };
    const WHITE: Color = .{ .blue = 255, .green = 255, .red = 255 };
};

pub const Framebuffer = struct {
    height: u64,
    width: u64,
    ptr: [*]u32,
    pitch: u64,
    bpp: u16,
    cursor: u64,

    pub fn init(ptr: u64, height: u64, width: u64, pitch: u64, bpp: u16) @This() {
        return .{ .ptr = @ptrFromInt(ptr), .height = height, .width = width, .cursor = 0, .pitch = pitch, .bpp = bpp };
    }

    pub fn write(self: *@This(), color: Color) void {
        self.writeAt(color, self.cursor);

        self.cursor += 1;
    }

    pub fn print(self: *@This(), to_write: u8, x: usize, y: usize, font: *align(1) const psf2.Psf2) void {
        var iter = font.readGlyph(to_write);
        var offset: u64 = y;
        while (iter.iter()) |lines| {
            var bit: u16 = lines[1] | @as(u16, lines[2]) << 8;

            bit = bit >> 6;

            for (0..10) |i| {
                if ((bit & 1) == 1) {
                    self.writePixel(10 - i + x, offset, Color.WHITE);
                } else {
                    self.writePixel(10 - i + x, offset, Color.BLACK);
                }

                bit = bit >> 1;
            }

            offset += 1;
        }
    }

    pub fn print_str(
        self: *@This(),
        to_write: []const u8,
        x: usize,
        y: usize,
        font: *align(1) const psf2.Psf2,
    ) void {
        var offset_line: usize = 0;
        var column = x;
        for (to_write) |c| {
            if (c == '\n') {
                offset_line += 16;
                column = x;
                continue;
            }
            self.print(c, column, y + offset_line, font);
            column += 10;
        }
    }

    pub fn writePixel(self: *const @This(), x: usize, y: usize, color: Color) void {
        const pos = x + (self.pitch / @sizeOf(u32)) * y;
        self.ptr[pos] = @bitCast(color);
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
