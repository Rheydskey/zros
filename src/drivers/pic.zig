const outb = @import("../asm.zig").outb;

const PIC = struct {
    cmd: u16,
    data: u16,

    const Command = struct {
        const DISABLE = 0xFF;
    };

    pub fn disable(self: *const @This()) void {
        outb(self.data, @This().Command.DISABLE);
    }
};

pub const PIC1: PIC = .{ .cmd = 0x20, .data = 0x21 };

pub const PIC2: PIC = .{ .cmd = 0xA0, .data = 0xA1 };

pub fn disable_pic() void {
    PIC1.disable();
    PIC2.disable();
}
