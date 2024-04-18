pub const serial = @import("./drivers/serial.zig");

pub const lucida = @embedFile("./font/lucida-10x16.psf");

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
        const glyphs: [*]const u8 = @ptrCast(&self.glyphs);
        const bytesperlines: u32 = (self.header.width + 7) / 8;
        var glyph: u32 = 0;
        for (0..self.header.height) |y| {
            serial.print("\n{}\t", .{y});

            serial.print("{b:0>16}", .{glyphs[glyph]});

            glyph += bytesperlines;
        }
    }

    pub fn readGlyph() [*]u8 {}
};
