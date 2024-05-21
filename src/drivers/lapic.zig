const serial = @import("./serial.zig");
const acpi = @import("../acpi/acpi.zig");
const limine = @import("../limine_rq.zig");
const asm_utils = @import("../utils.zig");
const hpet = @import("./hpet.zig");

pub var lapic: ?Lapic = null;

const Lapic = struct {
    addr: u64,

    fn read(self: *const @This(), reg: u32) u32 {
        return @as(*align(1) volatile u32, @ptrFromInt(self.addr + reg)).*;
    }

    fn write(self: *const @This(), reg: u32, value: u32) void {
        @as(*align(1) volatile u32, @ptrFromInt(self.addr + reg)).* = value;
    }

    pub fn end_of_interrupt(self: @This()) void {
        self.write(Regs.EOI, 0);
    }

    const Regs = struct {
        const CPU_ID = 0x20;
        const EOI = 0x0b0;
        const SPURIOUS = 0x0f0;
        const ICR0 = 0x300;
        const ICR1 = 0x310;
        const LVT_TIMER = 0x320;
        const TIMER_INITCNT = 0x380;
        const TIMER_CURRCNT = 0x390;
        const TIMER_DIV = 0x3e0;
    };

    const ApicTimer = struct {
        const MASKED = 0x1000;

        const LAPIC_TIMER_IRQ = 32;
        const LAPIC_TIMER_PERIODIC = 0x20000;

        const Divisor = struct {
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

    const LAPIC_ENABLED = 0x800;
    const MSR_APIC_BASE = 0x1B;
    const SPURIOUS_ALL = 0xFF;
    const SPURIOUS_ENABLE_APIC = 0x100;
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

    _lapic.write(Lapic.Regs.LVT_TIMER, Lapic.ApicTimer.MASKED);

    const tick_in_10ms = 0xFFFF_FFFF - _lapic.read(Lapic.Regs.TIMER_CURRCNT);

    _lapic.write(Lapic.Regs.LVT_TIMER, Lapic.ApicTimer.LAPIC_TIMER_IRQ | Lapic.ApicTimer.LAPIC_TIMER_PERIODIC);

    _lapic.write(Lapic.Regs.TIMER_DIV, Lapic.ApicTimer.Divisor.APIC_TIMER_DIVIDE_BY_16);

    _lapic.write(Lapic.Regs.TIMER_INITCNT, tick_in_10ms / 10);
}

pub fn send_ipi(lapic_id: u32, vec: u32) void {
    var l = lapic.?;

    l.write(Lapic.Regs.ICR1, lapic_id);
    l.write(Lapic.Regs.ICR0, vec);
}

// pub fn startap(lapic_id: u32, vec: u32) void {}
