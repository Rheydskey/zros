const serial = @import("serial.zig");
const acpi = @import("./acpi.zig");
const limine = @import("./limine_rq.zig");
const asm_utils = @import("utils.zig");

const lapic: ?Lapic = null;

const Lapic = struct {
    addr: u64,

    fn read(self: *@This(), reg: u32) u32 {
        return @as(*align(1) volatile u32, @ptrFromInt(self.addr + reg)).*;
    }

    fn write(self: *@This(), reg: u32, value: u32) void {
        @as(*align(1) volatile u32, @ptrFromInt(self.addr + reg)).* = value;
    }

    fn end_of_interrupt(self: @This()) void {
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

    const LAPIC_ENABLED = 0x800;
    const MSR_APIC_BASE = 0x1B;
    const SPURIOUS_ALL = 0xFF;
    const SPURIOUS_ENABLE_APIC = 0x100;
};

pub fn init() void {
    var addr: Lapic = .{ .addr = acpi.madt.?.lapic_addr + limine.hhdm.response.?.offset };
    serial.println("lapic: {any}", .{addr});

    addr.write(Lapic.MSR_APIC_BASE, @truncate((asm_utils.read_msr(Lapic.MSR_APIC_BASE) | Lapic.LAPIC_ENABLED) & ~@as(u64, 1 << 10)));
    addr.write(Lapic.Regs.SPURIOUS, addr.read(Lapic.Regs.SPURIOUS) | Lapic.SPURIOUS_ALL | Lapic.SPURIOUS_ENABLE_APIC);
}
