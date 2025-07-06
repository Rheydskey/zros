const assembly = @import("../asm.zig");
const acpi = @import("../acpi/acpi.zig");
const limine_rq = @import("../limine_rq.zig");
const serial = @import("serial.zig");
const mmio = @import("../mem/mmio.zig");

pub const PciDevice = struct {
    bus: u8,
    device: u5,
    function: u3,

    device_id: u16,
    vendor_id: u16,

    header_type: u8,

    class: u8,
    subclass: u8,

    msi: ?u8,
    msix: ?u8,

    // For later
    bars: []PciBar,
    mmios: []PciMmio,

    pub fn from(bus: u8, device: u5, function: u3, device_id: u16, vendor_id: u16, header_type: u8, class: u8, subclass: u8) @This() {
        return .{
            .bus = bus,
            .device = device,
            .function = function,
            .device_id = device_id,
            .vendor_id = vendor_id,
            .header_type = header_type,
            .class = class,
            .subclass = subclass,
            .msi = null,
            .msix = null,
            .bars = &[0]PciBar{},
            .mmios = &[0]PciMmio{},
        };
    }

    pub fn fromPciAddr(addr: *const PciAddr) @This() {
        const vendor_id = addr.read(u16);
        const device_id = addr.addOffset(0x2).read(u16);
        const header_type = addr.addOffset(0xe).read(u8);
        const class = addr.addOffset(0xb).read(u8);
        const subclass = addr.addOffset(0xa).read(u8);

        return PciDevice.from(addr.bus_no, addr.device_no, addr.fn_no, device_id, vendor_id, header_type, class, subclass);
    }

    pub fn parseCaps(self: *@This()) void {
        var nextoff: u8 = self.offset(0x34).read(u8);
        while (nextoff != 0) {
            const id = self.offset(nextoff).read(u8);
            switch (id) {
                0x5 => self.msi = nextoff,
                0x11 => self.msix = nextoff,
                else => {},
            }
            nextoff = self.offset(nextoff + 1).read(u8);
        }
    }

    pub fn max_bar_count(self: *const PciDevice) u8 {
        return switch (self.header_type) {
            0x00 => 6,
            0x01 => 2,
            else => 0,
        };
    }

    pub fn offset(self: *const @This(), of: u8) PciAddr {
        return .{
            .fn_no = self.function,
            .device_no = self.device,
            .bus_no = self.bus,
            .offset = of,
        };
    }

    /// https://wiki.osdev.org/PCI#Command_Register
    pub const CommandFlag = struct {
        pub const IOSpace = 1;
        pub const MemorySpace = (1 << 1);
        pub const BusMaster = (1 << 2);
    };

    pub fn command(self: @This()) u16 {
        return self.offset(0x4).read(u16);
    }

    pub fn status(self: @This()) u16 {
        return self.offset(0x6).read(u16);
    }

    pub fn set_command(self: @This(), commandreg: u16) void {
        self.offset(0x4).write(u16, commandreg);
    }

    pub fn capabilities(_: @This()) ?void {
        // if (self.status() & (1 << 4) != (1 << 4)) {
        //     return null;
        // }
        // const cap_ptr = self.offset(0x34).read(u8) & ~0b11;
        // // 0x3C is the last register + 4
        // const cap = self.offset(0x3C + 4 + cap_ptr);

        return null;
    }

    pub fn set_master_flag(self: @This()) void {
        self.set_command(self.command() | CommandFlag.BusMaster);
    }

    pub fn set_mmio_flag(self: @This()) void {
        self.set_command(self.command() | CommandFlag.MemorySpace);
    }

    pub fn bar(self: *const PciDevice, n: u8) ?PciBar {
        if (n > self.max_bar_count()) {
            return null;
        }

        const pcibar = PciBar.fromBarAddr(&self.offset(0x10 + 4 * n));
        if (pcibar.Mmio32.base == 0) {
            return null;
        }

        return pcibar;
    }
};

pub const PciMmio = struct {
    pcimmio: mmio.Mmio,
};

pub const PciBar = union(enum) {
    Mmio64: struct {
        base: u64,
        length: u64,
        prefetchable: bool,
        mmio: mmio.Mmio,
    },
    Mmio32: struct {
        base: u64,
        length: u64,
        prefetchable: bool,
        mmio: mmio.Mmio,
    },
    Io: struct {
        base: u64,
        length: u64,
    },

    const IS_IO = 0x1;

    fn getLength(addr: *const PciAddr) usize {
        const previous = addr.*.read(u32);
        addr.*.write(u32, ~@as(u32, 0));
        const size = (~addr.*.read(u32)) + 1;
        addr.*.write(u32, previous);
        return size;
    }

    pub fn fromBarAddr(addr: *const PciAddr) PciBar {
        const value = addr.*.read(u32);
        const is_io = value & IS_IO == IS_IO;
        const length = PciBar.getLength(addr);

        if (is_io) {
            return .{
                .Io = .{
                    .base = value & 0xfffffffc,
                    .length = length,
                },
            };
        }

        const is_64bits = (value >> 1) & 0b11 == 0b11;

        const base = switch (is_64bits) {
            false => value & 0xfffffff0,
            true => blk: {
                var upper_addr = addr.*;
                upper_addr.offset += 4;
                const upper = upper_addr.read(u32);
                break :blk (@as(u64, value) & 0xfffffff0) | @as(u64, upper) << 32;
            },
        };

        const prefetchable = value & 0b1000 == 0b1000;

        const pcimmio = mmio.Mmio.fromPhys(base, length / 4096);

        if (is_64bits) {
            return .{
                .Mmio64 = .{
                    .base = base,
                    .length = length,
                    .prefetchable = prefetchable,
                    .mmio = pcimmio,
                },
            };
        }

        return .{
            .Mmio32 = .{
                .base = base,
                .length = length,
                .prefetchable = prefetchable,
                .mmio = pcimmio,
            },
        };
    }
};

pub const PciAddr = packed struct(u32) {
    offset: u8 = 0,
    fn_no: u3,
    device_no: u5,
    bus_no: u8,
    reserved: u7 = 0,
    is_enable: bool = true,

    pub fn addOffset(self: @This(), offset: u8) @This() {
        return .{
            .fn_no = self.fn_no,
            .offset = self.offset + offset,
            .device_no = self.device_no,
            .bus_no = self.bus_no,
            .reserved = self.reserved,
            .is_enable = self.is_enable,
        };
    }

    pub fn read(self: @This(), comptime size: type) size {
        const mcfg = acpi.mcfg.?;

        const entry: *align(1) acpi.Mcfg.Configuration = mcfg.get_entry_of_bus(self.bus_no) orelse @panic("PCI CANNOT READ");

        return entry.read(self, size);
    }

    pub fn write(self: @This(), comptime size: type, value: size) void {
        const mcfg = acpi.mcfg.?;

        const entry = mcfg.get_entry_of_bus(self.bus_no) orelse @panic("PCI CANNOT WRITE");

        return entry.write(self, size, value);
    }

    // pub fn get_addr(self: @This(), cfg: acpi.Mcfg.Configuration) u64 {
    //     const addr: u64 = (@as(u64, self.bus_no - cfg.start) << 20 | @as(u64, self.device_no) << 15 | @as(u64, self.fn_no) << 12);
    //     return addr + limine_rq.hhdm.response.?.offset + cfg.base_addr + self.offset;
    // }
};

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

// FROM: https://admin.pci-ids.ucw.cz/read/PD/
const PciClass = enum {
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

    pub fn from(x: u8) @This() {
        return switch (x) {
            0 => @This().UnclassifiedDevice,
            1 => @This().MassStorage,
            2 => @This().Network,
            3 => @This().Display,
            4 => @This().Multimedia,
            5 => @This().Memory,
            6 => @This().Bridge,
            7 => @This().Communication,
            8 => @This().GenericSystemPeripheral,
            9 => @This().InputDevice,
            0xA => @This().DockingStation,
            0xB => @This().Processor,
            0xC => @This().SerialBus,
            0xD => @This().Wireless,
            0xE => @This().Intelligent,
            0xF => @This().SatelliteCommunications,
            0x10 => @This().Encryption,
            0x11 => @This().SignalProcessing,
            0x12 => @This().ProcessingAccelerator,
            0x13 => @This().NonEssentialInstrumentation,
            0x40 => @This().Coprocessor,
            0xFF => @This().Unassigned,
            else => @This().Unknown,
        };
    }
};

pub fn scan() void {
    for (0..32) |slot_usize| {
        const slot: u5 = @intCast(slot_usize);
        var func: u3 = 0;
        while (func < 7) : (func += 1) {
            const addr: PciAddr = .{
                .bus_no = 0,
                .device_no = slot,
                .fn_no = func,
                .offset = 0x0,
            };

            var device = PciDevice.fromPciAddr(&addr);

            if (device.vendor_id == 0xFFFF) {
                continue;
            }

            if (device.status() & (1 << 4) == (1 << 4)) {
                device.parseCaps();
            }

            serial.println("{any}", .{device});
            if (device.header_type == 0x0) {
                for (0..6) |n| {
                    serial.println("BAR {} = {any}", .{ n, device.bar(@intCast(n)) });
                }

                const class = PciClass.from(device.class);

                if (class == .Multimedia and device.subclass == 3) {
                    @import("audio.zig").init(&device) catch |err| {
                        serial.println("{any}", .{err});
                    };
                }
            }
        }
    }
}
