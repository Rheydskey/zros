pub const serial = @import("./drivers/serial.zig");

// http://www.zap.org.au/projects/console-fonts-lucida/
pub const lucida = @embedFile("./font/lucida-10x16.psf");

pub const GlyphIter = struct {
    base: [*]const u8,
    cur: u32 = 0,
    max: u32,
    step: u32 = 2,

    pub fn iter(self: *@This()) ?u16 {
        if (self.cur + self.step > self.max) {
            return null;
        }

        const high_part = self.base[self.cur];
        const low_part = self.base[self.cur + 1];
        self.cur += self.step;

        return (@as(u16, high_part) << 8 | @as(u16, low_part)) >> 6;
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

pub const Psf2 = packed struct {
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
        const glyphs: [*]const u16 = @alignCast(@ptrCast(&self.glyphs));
        const bytesperlines: u32 = (self.header.width + 7) / 16;
        const glyph: u32 = (self.header.glyph_size * nb) / 2;

        return GlyphIter{
            .base = @ptrCast(glyphs[glyph..]),
            .max = self.header.height * bytesperlines * 2,
        };
    }
};

test "read" {
    const std = @import("std");

    const a: *align(1) const Psf2 = @ptrCast(lucida);

    var glyph = a.readGlyph(0xDB);

    while (glyph.iter()) |i| {
        try std.testing.expectFmt("1111111111", "{b}", .{i});
    }
}

test "read_a" {
    const std = @import("std");

    const a: *align(1) const Psf2 = @ptrCast(lucida);

    var glyph = a.readGlyph(0x61);

    for (0..6) |_| {
        const value = glyph.iter();
        try std.testing.expectFmt("0", "{b}", .{value.?});
    }

    if (glyph.iter()) |v| {
        try std.testing.expectFmt("11110000", "{b}", .{v});
    }
}

test "read_a0" {
    const std = @import("std");

    const a: *align(1) const Psf2 = @ptrCast(lucida);

    var glyph = a.readGlyph(0xA0);

    for (0..8) |i| {
        const value = glyph.iter();
        if (i % 2 == 0) {
            try std.testing.expectFmt("101010101", "{b}", .{value.?});
        } else {
            try std.testing.expectFmt("1010101010", "{b}", .{value.?});
        }
    }
}
