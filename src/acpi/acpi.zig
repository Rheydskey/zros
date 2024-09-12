const lapic = @import("../drivers/lapic.zig");
const ioapic = @import("../drivers/ioapic.zig");
const serial = @import("../drivers/serial.zig");
const limine = @import("limine");
const limine_rq = @import("../limine_rq.zig");
const std = @import("std");
const hpet = @import("../drivers/hpet.zig");
const disable_pic = @import("../drivers/pic.zig").disable_pic;

pub var rspt: ?*align(1) Rspt = undefined;
pub var rsdp: ?*align(1) Rsdp = undefined;
pub var madt: ?*align(1) Madt = undefined;
pub var xspt: ?*align(1) Xspt = undefined;
pub var cpu_count: u32 = 0;

pub const AcpiHeader = packed struct(u288) {
    signature: u32,
    length: u32,
    revision: u8,
    checksum: u8,
    oem_id: u48,
    oem_table_id: u64,
    oem_revision: u32,
    creator_id: u32,
    creator_revision: u32,
};

const Xspt = packed struct {
    header: AcpiHeader,
    stdAddr: void,

    pub inline fn length(self: *align(1) @This()) u64 {
        return @divExact(self.header.length - @sizeOf(AcpiHeader), @sizeOf(u64));
    }

    pub fn get(self: *align(1) @This(), name: *const []const u8) !*Xspt {
        const entries = @as([*]u64, @alignCast(@ptrCast(&self.stdAddr)))[0..self.length()];
        for (entries) |entry| {
            const ptr: *Xspt = @ptrFromInt(entry + limine_rq.hhdm.response.?.offset);
            const signature_as_slice: [*]u8 = @ptrCast(&ptr.header.signature);

            if (std.mem.eql(u8, signature_as_slice[0..4], name.*)) {
                return ptr;
            }
        }

        return error.NotFound;
    }

    pub fn get_apic(self: *align(1) @This()) !*align(1) Madt {
        return @ptrCast(try self.get(&"APIC"));
    }
};

const Rspt = packed struct(u288) {
    header: AcpiHeader,
    stdAddr: void,

    pub inline fn length(self: *align(1) @This()) u32 {
        return @divExact(self.header.length - @sizeOf(AcpiHeader), @sizeOf(u32));
    }

    pub fn get(self: *align(1) @This(), name: *const []const u8) !*Rspt {
        const entries = @as([*]u32, @alignCast(@ptrCast(&self.stdAddr)))[0..self.length()];
        for (entries) |entry| {
            const ptr: *Rspt = @ptrFromInt(entry + limine_rq.hhdm.response.?.offset);
            const signature_as_slice: [*]u8 = @ptrCast(&ptr.header.signature);

            if (std.mem.eql(u8, signature_as_slice[0..4], name.*)) {
                return ptr;
            }
        }

        return error.NotFound;
    }

    pub fn get_apic(self: *align(1) @This()) !*align(1) Madt {
        return @ptrCast(try self.get(&"APIC"));
    }
};

pub const Madt = packed struct {
    header: AcpiHeader,
    lapic_addr: u32,
    flags: u32,
    entries: void,

    pub fn read_entries(self: *align(1) @This()) void {
        var entry: ?*Madt.MadtEntryHeader = undefined;
        var i: usize = 0;
        while (i < self.header.length - @sizeOf(@This())) {
            entry = @ptrFromInt(@intFromPtr(&self.entries) + i);
            serial.println("{any}", .{entry});

            switch (entry.?.entry_type) {
                0 => {
                    const lapic_entry: *align(1) Madt.ProcessorLocalApic = @ptrCast(&entry.?.entry);
                    serial.println("{any}", .{lapic_entry});
                    cpu_count += 1;
                },
                1 => {
                    const ioapic_struct: *align(1) Madt.IoApic = @ptrCast(&entry.?.entry);
                    serial.println("{any}", .{ioapic_struct});
                },

                2 => {
                    const iso: *align(1) Madt.Iso = @ptrCast(entry);
                    serial.println("{any}", .{iso});
                },

                else => {
                    serial.println("UNSUPPORTED ({})", .{entry.?.entry_type});
                },
            }

            i += @max(@sizeOf(MadtEntryHeader), entry.?.length);
        }

        serial.println("CPU COUNT: {}", .{cpu_count});
    }

    pub fn get_iso(self: *align(1) @This(), irq: u8) ?*align(1) Iso {
        var entry: ?*Madt.MadtEntryHeader = undefined;
        var i: usize = 0;
        while (i < self.header.length - @sizeOf(@This())) {
            entry = @ptrFromInt(@intFromPtr(&self.entries) + i);
            if (entry.?.entry_type == 2) {
                const iso: *align(1) Madt.Iso = @ptrCast(entry);
                if (iso.irq_src == irq) {
                    return iso;
                }
            }

            i += @max(@sizeOf(MadtEntryHeader), entry.?.length);
        }

        return null;
    }

    pub fn get_ioapic(self: *align(1) @This()) !*align(1) IoApic {
        var entry: ?*Madt.MadtEntryHeader = undefined;
        var i: usize = 0;
        while (i < self.header.length - @sizeOf(@This())) {
            entry = @ptrFromInt(@intFromPtr(&self.entries) + i);

            if (entry.?.entry_type == 1) {
                return @ptrCast(entry.?);
            }

            i += @max(@sizeOf(MadtEntryHeader), entry.?.length);
        }

        return error.NotFound;
    }

    pub const MadtEntryHeader = packed struct {
        entry_type: u8,
        length: u8,
        entry: void,
    };

    pub const Iso = packed struct {
        header: Madt.MadtEntryHeader,
        bus_src: u8,
        irq_src: u8,
        gsi: u32,
        flags: u16,
    };

    pub const IoApic = packed struct {
        header: Madt.MadtEntryHeader,
        ioapic: ioapic.IoApic,
    };

    pub const ProcessorLocalApic = packed struct {
        processor_id: u8,
        apic_id: u8,
        flags: packed struct(u32) { is_enabled: bool, is_online_capable: bool, other: u30 },
    };
};

const Rsdp = packed struct(u288) {
    signature: u64,
    checksum: u8,
    oem_id: u48,
    revision: u8,
    rsdt: u32,
    length: u32,
    xsdt: u64,
    extend_checksum: u8,
    reserved: u24,

    pub inline fn get_xsdt(self: *align(1) @This()) !*align(1) Xspt {
        if (self.revision <= 1) {
            return error.RevisionTooLow;
        }

        return @ptrFromInt(self.xsdt + limine_rq.hhdm.response.?.offset);
    }

    pub inline fn get_rsdt(self: *align(1) @This()) !*align(1) Rspt {
        if (self.revision > 1) {
            serial.println("DEPRECATED with revision 2.\n You should use xsdt", .{});
        }

        return @ptrFromInt(@as(u64, self.rsdt) + limine_rq.hhdm.response.?.offset);
    }
};

pub fn get_rspd() !*Rsdp {
    const response = limine_rq.rspd.response orelse return error.NoRspd;
    return @alignCast(@ptrCast(response.address));
}

pub const Mcfg = packed struct(u352) {
    header: AcpiHeader,
    reserved: u64,
    configuration: void,

    pub const Configuration = packed struct(u128) {
        base: u64,
        pci_group: u16,
        start: u8,
        end: u8,
        reserved: u32,
    };

    pub fn get_configuration(self: *align(1) @This()) ?Configuration {
        const ptr: *align(1) Configuration = @ptrCast(&self.configuration);

        return ptr.*;
    }

    pub fn nb_of_entry(self: *align(1) @This()) usize {
        return (self.header.length - @sizeOf(Mcfg)) / @sizeOf(Configuration);
    }
};

pub fn init() !void {
    disable_pic();

    const response = limine_rq.rspd.response orelse return error.NoRspd;

    rsdp = @alignCast(@ptrCast(response.address));

    serial.println("{any}", .{rsdp});
    if (rsdp.?.revision > 1) {
        xspt = try rsdp.?.get_xsdt();
        serial.println("{any}", .{xspt});

        madt = try xspt.?.get_apic();
    } else {
        rspt = try rsdp.?.get_rsdt();
        serial.println("{any}", .{rspt});

        madt = try rspt.?.get_apic();
    }

    madt.?.read_entries();

    try lapic.init();
    try hpet.init();

    var io_apic = (try madt.?.get_ioapic()).ioapic;
    io_apic.init();

    lapic.init_timer();
}
