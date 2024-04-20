const assembly = @import("../asm.zig");

pub const PciAddr = packed struct(u32) {
    offset: u8 = 0,
    fn_no: u3,
    device_no: u5,
    bus_no: u8,
    reserved: u7 = 0,
    is_enable: bool = true,

    pub fn read_config(self: @This()) u16 {
        assembly.outl(Pci.Regs.CONFIG_ADDRESS, @bitCast(self));
        return assembly.inw(Pci.Regs.CONFIG_DATA);
    }
};

pub const Pci = struct {
    bus: u8,
    slot: u5,
    function: u3,

    // FROM: https://admin.pci-ids.ucw.cz/read/PD/
    const Class = enum {
        UnclassifiedDevice,
        MassStorage,
        Network,
        Display,
        Multimedia,
        Memory,
        Bridge,
        Communication,
        GenericSystemPeripheral,
        InputDevice,
        DockingStation,
        Processor,
        SerialBus,
        Wireless,
        Intelligent,
        SatelliteCommunications,
        Encryption,
        SignalProcessing,
        ProcessingAccelerator,
        NonEssentialInstrumentation,
        Coprocessor,
        Unassigned,
        Unknown,
    };

    pub fn value2class(value: u8) Class {
        return switch (value) {
            0 => Class.UnclassifiedDevice,
            1 => Class.MassStorage,
            2 => Class.Network,
            3 => Class.Display,
            4 => Class.Multimedia,
            5 => Class.Memory,
            6 => Class.Bridge,
            7 => Class.Communication,
            8 => Class.GenericSystemPeripheral,
            9 => Class.InputDevice,
            0xA => Class.DockingStation,
            0xB => Class.Processor,
            0xC => Class.SerialBus,
            0xD => Class.Wireless,
            0xE => Class.Intelligent,
            0xF => Class.SatelliteCommunications,
            0x10 => Class.Encryption,
            0x11 => Class.SignalProcessing,
            0x12 => Class.ProcessingAccelerator,
            0x13 => Class.NonEssentialInstrumentation,
            0x40 => Class.Coprocessor,
            0xFF => Class.Unassigned,
            else => Class.Unknown,
        };
    }

    const Regs = struct {
        const CONFIG_ADDRESS = 0xCF8;
        const CONFIG_DATA = 0xCFC;
    };

    pub fn new(bus: u8, slot: u5, function: u3) Pci {
        return .{ .bus = bus, .slot = slot, .function = function };
    }

    pub fn addr(self: @This(), offset: u8) PciAddr {
        const pci_addr: PciAddr = .{
            .fn_no = self.function,
            .device_no = self.slot,
            .bus_no = self.bus,
            .offset = offset,
        };

        return pci_addr;
    }

    pub fn vendor_id(self: @This()) u16 {
        return self.addr(0x0).read_config();
    }

    pub fn device_id(self: @This()) u16 {
        return self.addr(0x2).read_config();
    }

    pub fn command(self: @This()) u16 {
        return self.addr(0x4).read_config();
    }

    pub fn status(self: @This()) u16 {
        return self.addr(0x6).read_config();
    }

    pub fn class(self: @This()) u8 {
        return @truncate(self.addr(0xb).read_config());
    }

    pub fn subclass(self: @This()) u8 {
        return @truncate(self.addr(0xa).read_config());
    }

    pub fn header_type(self: @This()) u8 {
        return @truncate(self.addr(0xe).read_config());
    }

    pub fn bar(self: @This(), n: u8) !u32 {
        if (n > 5) {
            return error.BarOverflow;
        }

        return @as(u32, self.addr(0x12 + 4 * n).read_config()) >> 16 | self.addr(0x10 + 4 * n).read_config();
    }

    pub fn print(self: @This()) void {
        @import("./serial.zig").println("At slot {}, Vendor {X}:{X} Class: {x}:{x} HeaderType: {x}", .{ self.slot, self.vendor_id(), self.device_id(), self.class(), self.subclass(), self.header_type() });
    }
};

pub fn scan() void {
    for (0..32) |slot_usize| {
        const slot: u5 = @intCast(slot_usize);
        const a = Pci.new(0, slot, 0);
        if (a.vendor_id() == 0xFFFF) {
            continue;
        }

        @import("serial.zig").println("", .{});
        a.print();
        @import("serial.zig").println("VF", .{});
        var function: u3 = 1;
        while (function < 7) : (function += 1) {
            const vf = Pci.new(0, slot, function);

            if (vf.vendor_id() == 0xFFFF) {
                continue;
            }

            vf.print();
        }

        if (a.header_type() == 0x0) {
            for (0..6) |n| {
                @import("serial.zig").println("BAR {} = {!}", .{ n, a.bar(@intCast(n)) });
            }
        }
    }
}
