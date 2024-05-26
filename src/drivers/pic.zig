const outb = @import("../asm.zig").outb;

const PIC = struct {
    cmd: u16,
    data: u16,
};

pub const PIC1: PIC = .{ .cmd = 0x20, .data = 0x21 };

pub const PIC2: PIC = .{ .cmd = 0xA0, .data = 0xA1 };

pub fn disable_pic() void {
    outb(PIC1.data, 0xff);
    outb(PIC2.data, 0xff);
}
