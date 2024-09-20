const acpi = @import("../acpi/acpi.zig");
const inb = @import("../asm.zig").inb;
const outb = @import("../asm.zig").outb;

pub const PS2 = struct {
    const Regs = struct {
        const DATA = 0x60;
        const STATUS_COMMAND = 0x64;
    };

    const Command = struct {
        const DISABLE_SECOND_PORT = 0xA7;
        const ENABLE_SECOND_PORT = 0xA8;
        const DISABLE_FIRST_PORT = 0xAD;
        const ENABLE_FIRST_PORT = 0xAE;
        const READ_CONFIG = 0x20;
        const WRITE_CONFIG = 0x60;
    };

    const Config = struct {
        const ENABLE_FIRST_PORT_INTERRUPT = (1 << 0);
        const FIRST_PORT_TRANSLATION = (1 << 6);
    };

    pub fn write(
        reg: u16,
        value: u8,
    ) void {
        while ((inb(Regs.STATUS_COMMAND) & 2) != 0) {}
        outb(reg, value);
    }

    pub fn read(
        reg: u16,
    ) u8 {
        while ((inb(Regs.STATUS_COMMAND) & 1) == 0) {}
        return inb(reg);
    }

    pub fn read_config() u8 {
        write(Regs.STATUS_COMMAND, Command.READ_CONFIG);
        return read(Regs.DATA);
    }

    pub fn write_config(config: u8) void {
        write(Regs.STATUS_COMMAND, Command.WRITE_CONFIG);
        return write(Regs.DATA, config);
    }
};

pub fn init() !void {
    PS2.write(PS2.Regs.STATUS_COMMAND, PS2.Command.DISABLE_FIRST_PORT);
    PS2.write(PS2.Regs.STATUS_COMMAND, PS2.Command.DISABLE_SECOND_PORT);

    var ps2_config = PS2.read_config();

    ps2_config |= PS2.Config.ENABLE_FIRST_PORT_INTERRUPT | PS2.Config.FIRST_PORT_TRANSLATION;

    PS2.write_config(ps2_config);

    PS2.write(PS2.Regs.STATUS_COMMAND, PS2.Command.ENABLE_FIRST_PORT);

    var io_apic = (try acpi.madt.?.get_ioapic()).ioapic;

    // Redirect keyboard
    io_apic.redirect(0, 33, 1);
}
