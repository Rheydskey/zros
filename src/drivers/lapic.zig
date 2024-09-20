const serial = @import("./serial.zig");
const acpi = @import("../acpi/acpi.zig");
const limine = @import("../limine_rq.zig");
const asm_utils = @import("../utils.zig");
const hpet = @import("./hpet.zig");

pub var lapic: ?Lapic = null;

pub const Lapic = struct {
    addr: u64,

    pub fn read(self: *const @This(), reg: u32) u32 {
        return @as(*align(1) volatile u32, @ptrFromInt(self.addr + reg)).*;
    }

    pub fn write(self: *const @This(), reg: u32, value: u32) void {
        @as(*align(1) volatile u32, @ptrFromInt(self.addr + reg)).* = value;
    }

    pub fn end_of_interrupt(self: @This()) void {
        self.write(Regs.EOI, 0);
    }

    pub const Regs = struct {
        pub const ERROR_STATUS = 0x280;
        pub const CPU_ID = 0x20;
        pub const EOI = 0x0b0;
        pub const SPURIOUS = 0x0f0;
        pub const ICR0 = 0x300;
        pub const ICR1 = 0x310;
        pub const LVT_TIMER = 0x320;
        pub const TIMER_INITCNT = 0x380;
        pub const TIMER_CURRCNT = 0x390;
        pub const TIMER_DIV = 0x3e0;
    };

    pub const ApicTimer = struct {
        pub const MASKED = 0x1000;

        pub const LAPIC_TIMER_IRQ = 32;
        pub const LAPIC_TIMER_PERIODIC = 0x20000;

        pub const Divisor = struct {
            const APIC_TIMER_DIVIDE_BY_2 = 0;
            const APIC_TIMER_DIVIDE_BY_4 = 1;
            const APIC_TIMER_DIVIDE_BY_8 = 2;
            const APIC_TIMER_DIVIDE_BY_16 = 3;
            const APIC_TIMER_DIVIDE_BY_32 = 4;
            const APIC_TIMER_DIVIDE_BY_64 = 5;
            const APIC_TIMER_DIVIDE_BY_128 = 6;
            const APIC_TIMER_DIVIDE_BY_1 = 7;
        };
    };

    pub const LAPIC_ENABLED = 0x800;
    pub const MSR_APIC_BASE = 0x1B;
    pub const SPURIOUS_ALL = 0xFF;
    pub const SPURIOUS_ENABLE_APIC = 0x100;
};

pub fn init() !void {
    lapic = .{ .addr = acpi.madt.?.lapic_addr + limine.hhdm.response.?.offset };
    serial.println("lapic: {any}", .{lapic});

    lapic.?.write(Lapic.MSR_APIC_BASE, @truncate((asm_utils.read_msr(Lapic.MSR_APIC_BASE) | Lapic.LAPIC_ENABLED) & ~@as(u64, 1 << 10)));
    lapic.?.write(Lapic.Regs.SPURIOUS, lapic.?.read(Lapic.Regs.SPURIOUS) | Lapic.SPURIOUS_ALL | Lapic.SPURIOUS_ENABLE_APIC);
}

pub fn init_timer() void {
    const _lapic = lapic.?;

    _lapic.write(Lapic.Regs.TIMER_DIV, Lapic.ApicTimer.Divisor.APIC_TIMER_DIVIDE_BY_16);
    _lapic.write(Lapic.Regs.TIMER_INITCNT, 0xFFFF_FFFF);

    hpet.hpet.?.sleep(10);

    const tick_in_10ms = 0xFFFF_FFFF - _lapic.read(Lapic.Regs.TIMER_CURRCNT);

    _lapic.write(Lapic.Regs.LVT_TIMER, Lapic.ApicTimer.MASKED);
    _lapic.write(Lapic.Regs.LVT_TIMER, Lapic.ApicTimer.LAPIC_TIMER_IRQ | Lapic.ApicTimer.LAPIC_TIMER_PERIODIC);
    _lapic.write(Lapic.Regs.TIMER_DIV, Lapic.ApicTimer.Divisor.APIC_TIMER_DIVIDE_BY_16);
    _lapic.write(Lapic.Regs.TIMER_INITCNT, tick_in_10ms / 10);
}

pub fn send_ipi(lapic_id: u32, vec: u32) void {
    var l = lapic.?;

    l.write(Lapic.Regs.ICR1, lapic_id);
    l.write(Lapic.Regs.ICR0, vec);
}
