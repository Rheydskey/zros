const acpi = @import("../acpi/acpi.zig");
const limine = @import("../limine_rq.zig");

pub var hpet: ?Hpet = null;
var clock: u64 = 0;

const AcpiHpet = packed struct(u448) {
    header: acpi.AcpiHeader,
    rev_id: u8,
    info: u8,
    vendor_id: u16,
    address_space: u8,
    register_bit_width: u8,
    register_bit_offset: u8,
    reserved: u8,
    address: u64,
    hpet_num: u8,
    minimum_tick: u16,
    page_protection: u8,
};

const Hpet = packed struct {
    addr: u64,

    pub fn write(self: *align(1) @This(), reg: u64, value: u64) void {
        @as(*align(1) volatile u64, @ptrFromInt(self.addr + reg)).* = value;
    }

    pub fn read(self: *@This(), reg: u64) u64 {
        return @as(*align(1) volatile u64, @ptrFromInt(self.addr + reg)).*;
    }

    const Regs = struct {
        const GENERAL_CAPABILITIES = 0x0;
        const GENERAL_CONFIGURATION = 0x10;
        const MAIN_COUNTER_VALUE = 0xF0;
    };

    const CONF_OFF = 0;
    const CONF_ON = 1;

    pub fn init(self: *@This()) void {
        clock = self.read(Regs.GENERAL_CAPABILITIES) >> 32;

        self.write(Regs.GENERAL_CONFIGURATION, Hpet.CONF_OFF);
        self.write(Regs.MAIN_COUNTER_VALUE, 0);
        self.write(Regs.GENERAL_CONFIGURATION, Hpet.CONF_ON);
    }

    pub fn sleep(self: *@This(), ms: u64) void {
        const max: u64 = self.read(Regs.MAIN_COUNTER_VALUE) + (ms * 1_000_000_000_000) / clock;

        while (self.read(Regs.MAIN_COUNTER_VALUE) < max) {}
    }
};

pub fn init() !void {
    const hpet_acpi: *align(1) AcpiHpet = @ptrCast(try acpi.xspt.?.get(&"HPET"));

    if (hpet_acpi.address_space == 1) {
        return error.UnsupportedSystemIo;
    }

    if (hpet_acpi.address == 0) {
        return error.WeirdAddr;
    }

    hpet = .{ .addr = hpet_acpi.address + limine.hhdm.response.?.offset };

    hpet.?.init();
}
