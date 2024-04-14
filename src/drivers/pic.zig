const assembly = @import("../asm.zig");

const PIC = struct {
    cmd: u16,
    data: u16,
    end_of_interrupt: *const fn () void,
};

pub const PIC1: PIC = .{ .cmd = 0x20, .data = 0x21, .end_of_interrupt = &end_of_pic1 };

pub fn end_of_pic1() void {
    assembly.outb(PIC1.cmd, ENDOFINTERRUPT);
}

pub const PIC2: PIC = .{ .cmd = 0xA0, .data = 0xA1, .end_of_interrupt = &end_of_pic2 };

pub fn end_of_pic2() void {
    assembly.outb(PIC2.cmd, ENDOFINTERRUPT);
}

const ENDOFINTERRUPT: u8 = 0x20;

const ICW = struct {
    const ICW1_INIT: u8 = 0x10;
    const ICW1_ICW4: u8 = 0x01;
};

pub fn load_pic() !void {
    assembly.outb(PIC1.cmd, ICW.ICW1_INIT | ICW.ICW1_ICW4);
    assembly.outb(PIC2.cmd, ICW.ICW1_INIT | ICW.ICW1_ICW4);

    assembly.outb(PIC1.data, 0x20);
    assembly.outb(PIC2.data, 0x28);

    assembly.outb(PIC1.data, 0x04);
    assembly.outb(PIC2.data, 0x02);

    assembly.outb(PIC1.data, 0x01);
    assembly.outb(PIC2.data, 0x01);

    assembly.outb(PIC1.data, 0x00);
    assembly.outb(PIC2.data, 0x00);
}
