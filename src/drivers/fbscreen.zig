const psf2 = @import("../psf.zig");
const std = @import("std");

pub var fb_ptr: ?Framebuffer = null;

const Glyph = struct {
    character: u8,
    font: *align(1) const psf2.Psf2,
    color_fg: Color,
    color_bg: Color,

    pub inline fn getColor(self: *const @This(), is_foreground: bool) Color {
        if (is_foreground) {
            return self.color_fg;
        }

        return self.color_bg;
    }

    pub fn writeGlyph(self: *const @This(), x: usize, y: usize, fb: *const Framebuffer) void {
        var lines = self.font.readGlyph(self.character);
        var offset: u64 = y;
        while (lines.iter()) |line| {
            var bit = line;

            for (0..10) |i| {
                fb.writePixel(10 - i + x, offset, self.getColor((bit & 1) == 1));

                bit >>= 1;
            }

            offset += 1;
        }
    }
};

pub const Color = packed struct(u32) {
    blue: u8,
    green: u8,
    red: u8,
    alpha: u8 = 255,

    const BLACK: Color = .{ .blue = 0, .green = 0, .red = 0 };
    const WHITE: Color = .{ .blue = 255, .green = 255, .red = 255 };
};

pub const ScreenWriter = struct {
    interface: std.Io.Writer,
    framebuffer: *Framebuffer,
    x: usize = 0,
    y: usize = 0,

    fn moveTo(self: *ScreenWriter, x: usize, y: usize) void {
        self.x = x;
        self.y = y;
    }

    pub fn reset(self: *ScreenWriter) void {
        self.moveTo(0, 0);
        self.framebuffer.reset();
    }

    pub fn moveCursor(self: *ScreenWriter, x: usize, y: usize) void {
        self.x = x;
        self.y = y;
    }

    pub fn previous(self: *ScreenWriter, length: usize) void {
        const width = self.framebuffer.width / self.framebuffer.font.header.width;
        self.y -|= length - (width - self.x) / width;
        self.x -|= length % width;
    }

    pub fn nextLine(self: *ScreenWriter) void {
        self.y += 1;
    }

    pub fn advance(self: *ScreenWriter, length: usize) void {
        const width = self.framebuffer.width / self.framebuffer.font.header.width;
        const heigth = self.framebuffer.height / self.framebuffer.font.header.height;
        self.x = (self.x + length) % width - 1;
        self.y = (self.y + (length / width) * self.framebuffer.font.header.height) % (heigth - 1);
    }

    fn writeChar(self: *ScreenWriter, byte: u8) void {
        if (byte == '\n') {
            const width = self.framebuffer.width / self.framebuffer.font.header.width;
            self.advance(width - self.x);
            return;
        }

        self.framebuffer.print(byte, self.x, self.y);
    }

    pub fn print(self: *ScreenWriter, comptime fmt: []const u8, args: anytype) void {
        return self.interface.print(fmt, args) catch {};
    }

    pub fn println(self: *ScreenWriter, comptime fmt: []const u8, args: anytype) void {
        return self.interface.print(fmt ++ "\n", args) catch {};
    }

    pub fn drain(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const w: *ScreenWriter = @alignCast(@fieldParentPtr("interface", io_w));

        var written: usize = data[data.len - 1].len * splat;

        for (data[0..data.len]) |chunk| {
            for (chunk) |byte| {
                w.writeChar(byte);
            }

            written += chunk.len;
        }

        for (0..splat) |_| {
            for (data[data.len - 1]) |byte| {
                w.writeChar(byte);
            }
        }
        io_w.end = 0;
        return written;
    }

    pub fn init(framebuffer: *Framebuffer) ScreenWriter {
        return .{
            .interface = .{
                .vtable = &.{
                    .drain = drain,
                },
                .buffer = &[_]u8{},
            },
            .framebuffer = framebuffer,
        };
    }
};

pub const Screen = struct {
    max_x: usize,
    max_y: usize,

    x: usize = 0,
    y: usize = 0,

    pub fn add(self: *@This(), to_add: usize) void {
        if (self.x + to_add > self.max_x) {
            self.y += 16 * ((self.x + to_add) / self.max_x);
            self.x = 0;
            return;
        }

        self.x += to_add;
    }

    pub fn remove(self: *@This(), to_remove: usize) void {
        self.x -|= to_remove;
    }

    pub fn nextLine(self: *@This()) void {
        self.x = 0;
        self.y += 16;
    }

    pub fn print(self: *@This(), to_write: u8) void {
        if (to_write == '\n') {
            self.nextLine();
            return;
        }

        if (fb_ptr) |fb| {
            fb.print(to_write, self.x, self.y);
            self.add(10);
        }
    }

    pub fn println(self: *@This(), to_write: []const u8) void {
        for (to_write) |c| {
            self.print(c);
        }
        self.nextLine();
    }
};

pub var screen: ?ScreenWriter = null;

pub const Framebuffer = struct {
    height: u64,
    width: u64,
    ptr: [*]u32,
    pitch: u64,
    bpp: u16,
    cursor: u64,
    font: *align(1) const psf2.Psf2,

    pub fn init(ptr: u64, height: u64, width: u64, pitch: u64, bpp: u16, font: *align(1) const psf2.Psf2) @This() {
        return .{ .ptr = @ptrFromInt(ptr), .height = height, .width = width, .cursor = 0, .pitch = pitch, .bpp = bpp, .font = font };
    }

    pub fn write(self: *@This(), color: Color) void {
        self.writeAt(color, self.cursor);

        self.cursor += 1;
    }

    pub fn print(self: *const @This(), to_write: u8, x: usize, y: usize) void {
        const glyph: Glyph = .{
            .character = to_write,
            .font = self.font,
            .color_fg = Color.BLACK,
            .color_bg = Color.WHITE,
        };
        glyph.writeGlyph(x, y, self);
    }

    pub fn print_str(
        self: *@This(),
        to_write: []const u8,
        x: usize,
        y: usize,
    ) void {
        var offset_line: usize = 0;
        var column = x;
        for (to_write) |c| {
            if (c == '\n') {
                offset_line += self.font.header.height;
                column = x;
                continue;
            }
            self.print(c, column, y + offset_line);
            column += self.font.header.width;
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

    pub fn reset(self: *Framebuffer) void {
        self.fillWith(struct {
            fn fill(_: u64, _: u64) Color {
                return Color.BLACK;
            }
        }.fill) catch {};
    }

    pub fn fillWith(self: *@This(), fill: fn (x: u64, y: u64) Color) !void {
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                self.write(fill(x, y));
            }
        }
    }
};
