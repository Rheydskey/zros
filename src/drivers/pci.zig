const assembly = @import("../asm.zig");
const acpi = @import("../acpi/acpi.zig");
const limine_rq = @import("../limine_rq.zig");
const serial = @import("serial.zig");

const CONFIG_ADDR: u32 = 0xCF8;
const CONFIG_DATA: u32 = 0xCFC;

pub const HeaderType = packed struct(u8) {
    header_type: u7,
    multi_func: bool,

    pub fn is_standard_header(self: @This()) bool {
        return self.header_type == 0x0;
    }

    pub fn is_pci_to_pci_header(self: @This()) bool {
        return self.header_type == 0x1;
    }

    pub fn is_cardbus_header(self: @This()) bool {
        return self.header_type == 0x2;
    }
};

pub const PciBar = struct {
    base: u64,
    length: u64,
    mmio: bool,
    is_64bits: bool,
};

pub const PciAddr = packed struct(u32) {
    offset: u8 = 0,
    fn_no: u3,
    device_no: u5,
    bus_no: u8,
    reserved: u7 = 0,
    is_enable: bool = true,

    pub fn legacy_read(self: @This(), comptime size: type) size {
        assembly.outl(CONFIG_ADDR, @bitCast(self));
        switch (size) {
            u8 => {
                return assembly.inb(CONFIG_DATA);
            },
            u16 => {
                return assembly.inw(CONFIG_DATA);
            },
            u32 => {
                return assembly.inl(CONFIG_DATA);
            },
            else => {
                @compileError("Should use u8, u16 or u32 as type");
            },
        }
    }

    pub fn legacy_write(self: @This(), comptime size: type, value: size) void {
        assembly.outl(CONFIG_ADDR, @bitCast(self));
        switch (size) {
            u8 => {
                return assembly.outb(CONFIG_DATA, value);
            },
            u16 => {
                return assembly.outw(CONFIG_DATA, value);
            },
            u32 => {
                return assembly.outl(CONFIG_DATA, value);
            },
            else => {
                @compileError("Should use u8, u16 or u32 as type");
            },
        }
    }

    pub fn read(self: @This(), comptime size: type) size {
        const mcfg = acpi.mcfg.?;

        const entry = mcfg.get_entry_of_bus(self.bus_no) orelse @panic("PCI CANNOT READ");

        return entry.read(self, size);
    }

    pub fn write(self: @This(), comptime size: type, value: size) void {
        const mcfg = acpi.mcfg.?;

        const entry = mcfg.get_entry_of_bus(self.bus_no) orelse @panic("PCI CANNOT WRITE");

        return entry.write(self, size, value);
    }

    pub fn get_addr(self: @This(), cfg: acpi.Mcfg.Configuration) u64 {
        const addr: u64 = (@as(u64, self.bus_no - cfg.start) << 20 | @as(u64, self.device_no) << 15 | @as(u64, self.fn_no) << 12);
        return addr + limine_rq.hhdm.response.?.offset + cfg.base + self.offset;
    }
};

pub const Pci = struct {
    bus: u8,
    slot: u5,
    function: u3,
    mcfg: acpi.Mcfg.Configuration,

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

        pub fn from(x: u8) Class {
            return switch (x) {
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
    };

    const Regs = struct {
        const CONFIG_ADDRESS = 0xCF8;
        const CONFIG_DATA = 0xCFC;
    };

    pub fn new(bus: u8, slot: u5, function: u3, mcfg: *align(1) const acpi.Mcfg.Configuration) Pci {
        return .{ .bus = bus, .slot = slot, .function = function, .mcfg = mcfg.* };
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
        return self.addr(0x0).read(u16);
    }

    pub fn device_id(self: @This()) u16 {
        return self.addr(0x2).read(u16);
    }

    pub fn command(self: @This()) u16 {
        return self.addr(0x4).read(u16);
    }

    pub fn status(self: @This()) u16 {
        return self.addr(0x6).read(u16);
    }

    pub fn class(self: @This()) u8 {
        return self.addr(0xb).read(u8);
    }

    pub fn subclass(self: @This()) u8 {
        return self.addr(0xa).read(u8);
    }

    pub fn header_type(self: @This()) HeaderType {
        return @bitCast(self.addr(0xe).read(u8));
    }

    pub fn set_command(self: @This(), command_index: u4, value: bool) void {
        const paddr = self.addr(0x4);

        var current = paddr.read(u16);
        const value_u16: u16 = if (value) 1 else 0;

        if (value) {
            current |= (value_u16 << command_index);
        } else {
            current &= ~(value_u16 << command_index);
        }

        paddr.write(u16, current);
    }

    pub fn set_master_flag(self: @This()) void {
        self.set_command(0x2, true);
    }

    pub fn set_mmio_flag(self: @This()) void {
        self.set_command(0x1, true);
    }

    const IS_IO: u32 = 1;
    const BAR_TYPE_MASK: u32 = 0x6;
    const BAR_TYPE_64BIT: u32 = 0x4;
    const BAR_PORT_MASK: u32 = 0xFFFF_FFFC;
    const BAR_MMIO_ADDR_MASK: u32 = 0xFFFF_FFF0;

    pub fn bar(self: @This(), n: u8) !?PciBar {
        if (n >= 6) {
            return error.BarOverflow;
        }

        const offset: u8 = 0x10 + 4 * n;

        var pcibar: PciBar = undefined;
        const pci_addr = self.addr(offset);
        const bar_lower = pci_addr.read(u32);

        const is_io: bool = (bar_lower & IS_IO) == 1;

        if (is_io) {
            return .{
                .base = bar_lower & BAR_PORT_MASK,
                .mmio = false,
                .length = 0,
                .is_64bits = false,
            };
        }

        const address = bar_lower & BAR_MMIO_ADDR_MASK;

        pci_addr.write(u32, BAR_MMIO_ADDR_MASK);
        const bar_size_low = pci_addr.read(u32);
        pci_addr.write(u32, address);

        if (bar_size_low == 0) {
            return null;
        }

        pcibar.mmio = true;
        pcibar.base = address;
        pcibar.length = ~(bar_size_low & 0xFFFF_FFF0) + 1;
        pcibar.is_64bits = (bar_lower & BAR_TYPE_MASK) == BAR_TYPE_64BIT;

        if (pcibar.is_64bits) {
            const pci_addr_upper = self.addr(offset + 4);

            const bar_upper = @as(u64, pci_addr_upper.read(u32));
            pcibar.base += (bar_upper << 32);
        }

        return pcibar;
    }

    pub fn print(self: @This()) void {
        serial.println("At slot {}, Vendor {X}:{X} Class: {any}:{x} HeaderType: {any}", .{ self.slot, self.vendor_id(), self.device_id(), Class.from(self.class()), self.subclass(), self.header_type() });
    }
};

pub fn scan(mcfg: *align(1) acpi.Mcfg.Configuration) void {
    for (0..32) |slot_usize| {
        const slot: u5 = @intCast(slot_usize);
        const device = Pci.new(0, slot, 0, mcfg);

        if (device.vendor_id() == 0xFFFF) {
            continue;
        }

        device.print();
        var function: u3 = 1;
        while (function < 7) : (function += 1) {
            const vf = Pci.new(0, slot, function, mcfg);

            if (vf.vendor_id() == 0xFFFF) {
                continue;
            }

            vf.print();
        }

        if (device.header_type().is_standard_header()) {
            for (0..6) |n| {
                serial.println("BAR {} = {any}", .{ n, device.bar(@intCast(n)) });
            }

            const class = Pci.Class.from(device.class());
            if (class == .Multimedia and device.subclass() == 3) {
                device.set_master_flag();
                device.set_mmio_flag();
                @import("audio.zig").init(&device, function, slot) catch |err| {
                    serial.println("{any}", .{err});
                };
            }
        }
    }
}
