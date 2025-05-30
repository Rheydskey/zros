const serial = @import("./serial.zig");
const limine_rq = @import("../limine_rq.zig");
const acpi = @import("../acpi/acpi.zig");

/// https://osdev.wiki/wiki/IOAPIC#IOREDTBL
pub const IoApicRedirect = packed struct(u64) {
    int_vec: u8 = 0,
    delivery_mode: DeliveryMode = .Fixed,
    destination_mode: DestinationMode = .Physical,
    delivery_status: bool = false,
    interrupt_pin: InterruptPinPolarity = .High,
    remote_irr: bool = false,
    trigger_mode: bool = false,
    interrupt_mask: bool = false,
    reserved: u39 = 0,
    destination: u8 = 0,

    const InterruptPinPolarity = enum(u1) {
        High = 0,
        Low = 1,
    };

    const DestinationMode = enum(u1) {
        Physical = 0,
        Logical = 1,
    };

    const DeliveryMode = enum(u3) {
        Fixed = 0b000,
        LowestPriority = 0b001,
        SystemManagementInterrupt = 0b010,
        NonMaskableInterrupt = 0b100,
        Init = 0b101,
        ExtInt = 0b111,
    };

    const IOAPIC_ACTIVE_HIGH_WHEN_LOW = (1 << 1);
    const IOAPIC_LEVEL_TRIGGER = (1 << 3);
};

pub const IoApic = packed struct {
    ioapic_id: u8,
    reserved: u8,
    ioapic_addr: u32,
    gsib: u32,

    pub fn write(self: *align(1) @This(), reg: u32, value: u32) void {
        const base: u64 = self.ioapic_addr + limine_rq.hhdm.response.?.offset;

        serial.println("Will write at {x}", .{base});
        @as(*volatile u32, @ptrFromInt(base)).* = reg;
        @as(*volatile u32, @ptrFromInt(base + 16)).* = value;
    }

    pub fn redirect_gsi(self: *align(1) @This(), lapic_id: u32, intno: u8, gsi: u32, flags: u16) void {
        var acpi_redirect: IoApicRedirect = .{
            .int_vec = intno,
        };

        if ((flags & IoApicRedirect.IOAPIC_ACTIVE_HIGH_WHEN_LOW) == IoApicRedirect.IOAPIC_ACTIVE_HIGH_WHEN_LOW) {
            acpi_redirect.interrupt_pin = .Low;
        }

        if ((flags & IoApicRedirect.IOAPIC_LEVEL_TRIGGER) == IoApicRedirect.IOAPIC_LEVEL_TRIGGER) {
            acpi_redirect.trigger_mode = true;
        }

        acpi_redirect.destination = @intCast(lapic_id);

        const redirect_table: u32 = (gsi - self.gsib) * 2 + 16;
        const struct_as_u64: u64 = @bitCast(acpi_redirect);
        serial.println("{}", .{redirect_table});

        self.write(redirect_table, @intCast(struct_as_u64));
        self.write(redirect_table + 1, @intCast(struct_as_u64 >> 32));
    }

    pub fn redirect(self: *align(1) @This(), lapic_id: u32, intno: u8, irq: u8) void {
        if (acpi.madt.?.get_iso(irq)) |iso| {
            serial.println("Will redirect {} to {} with GSI flags", .{ intno, irq });
            self.redirect_gsi(lapic_id, intno, iso.gsi, iso.flags);
        } else {
            serial.println("Will redirect {} to {} with 0 flags", .{ intno, irq });
            self.redirect_gsi(lapic_id, intno, irq, 0);
        }
    }

    pub fn init(self: *align(1) @This()) void {
        for (0..16) |i| {
            // i + 32 because there is 32 exceptions
            self.redirect(
                0,
                @as(u8, @intCast(i)) + 32,
                @as(u8, @intCast(i)),
            );
        }
    }
};
