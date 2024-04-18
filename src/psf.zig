pub const serial = @import("./drivers/serial.zig");

pub const lucida = @embedFile("./font/lucida-10x16.psf");

pub const GlyphIter = struct {
    base: [*]const u8,
    cur: u32 = 0,
    max: u32,
    step: u32 = 1,

    pub fn iter(self: *@This()) ?[]const u8 {
        if (self.cur + self.step > self.max) {
            return null;
        }

        const result = self.base[self.cur..(self.cur + self.step)];
        self.cur += self.step;

        return result;
    }
};

pub const Psf2Header = packed struct(u256) {
    magic_bytes: u32,
    version: u32,
    header_size: u32,
    flags: u32,
    length: u32,
    glyph_size: u32,
    height: u32,
    width: u32,

    const Flags = struct {};
};

pub const Psf2 = struct {
    header: Psf2Header,
    glyphs: void,

    pub fn printHeader(self: *align(1) const @This()) void {
        serial.println("{any}", .{self.header});
    }

    pub fn readall(self: *align(1) const @This()) void {
        for (0..self.header.length) |nb| {
            serial.println("", .{});
            var iter = self.readGlyph(@intCast(nb));
            while (iter.iter()) |l| {
                serial.print("\n{b:0>8}", .{l});
            }
        }
    }

    pub fn readGlyph(self: *align(1) const @This(), nb: u8) GlyphIter {
        const glyphs: [*]const u8 = @ptrCast(&self.glyphs);
        const bytesperlines: u32 = (self.header.width + 7) / 8;
        const glyph: u32 = self.header.glyph_size * nb;

        return GlyphIter{ .base = glyphs[glyph..], .max = self.header.height * bytesperlines, .step = 2 };
    }
};
