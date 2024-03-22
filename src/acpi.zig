const serial = @import("serial.zig");
const limine = @import("limine");
const limine_rq = @import("./limine_rq.zig");
const std = @import("std");

pub var rspt: ?*align(1) Rspt = undefined;
pub var rsdp: ?*align(1) Rsdp = undefined;
pub var madt: ?*align(1) Madt = undefined;
pub var xspt: ?*align(1) Xspt = undefined;

const AcpiSDT = extern struct {
    signature: [4]u8,
    length: u32,
    revision: u8,
    checksum: u8,
    oem_id: [6]u8,
    oem_table_id: [8]u8,
    oem_revision: u32,
    creator_id: u32,
    creator_revision: u32,

    comptime {
        if (!(@sizeOf(@This()) == 36)) {
            @compileError("Bad size for" ++ @typeName(@This()));
        }
    }
};

const Xspt = extern struct {
    header: AcpiSDT,
    stdAddr: [0]u64 align(4),

    pub inline fn length(self: *align(1) @This()) u64 {
        return @divExact(self.header.length - @sizeOf(AcpiSDT), @sizeOf(u64));
    }

    pub fn get(self: *align(1) @This(), name: *const []const u8) !*Xspt {
        const entries = @as([*]u64, &self.stdAddr)[0..self.length()];
        for (entries) |entry| {
            const ptr: *Xspt = @ptrFromInt(entry + limine_rq.hhdm.response.?.offset);

            if (std.mem.eql(u8, &ptr.header.signature, name.*)) {
                return ptr;
            }
        }

        return error.NotFound;
    }

    pub fn get_apic(self: *align(1) @This()) !*align(1) Madt {
        return @ptrCast(try self.get(&"APIC"));
    }
};

const Rspt = extern struct {
    header: AcpiSDT,
    stdAddr: [0]u32,

    pub inline fn length(self: *align(1) @This()) u32 {
        return @divExact(self.header.length - @sizeOf(AcpiSDT), @sizeOf(u32));
    }

    pub fn get(self: *align(1) @This(), name: *const []const u8) !*Rspt {
        const entries = @as([*]u32, &self.stdAddr)[0..self.length()];
        for (entries) |entry| {
            const ptr: *Rspt = @ptrFromInt(entry + limine_rq.hhdm.response.?.offset);

            if (std.mem.eql(u8, &ptr.header.signature, name.*)) {
                return ptr;
            }
        }

        return error.NotFound;
    }

    pub fn get_apic(self: *align(1) @This()) !*align(1) Madt {
        return @ptrCast(try self.get(&"APIC"));
    }

    comptime {
        if (!(@sizeOf(@This()) == 36)) {
            @compileError("Bad size for " ++ @typeName(@This()));
        }
    }
};

const Madt = extern struct {
    header: AcpiSDT,
    lapic_addr: u32,
    flags: u32,
    entries: [0]u8,

    pub fn read_entries(self: *align(1) @This()) void {
        var entry: ?*Madt.MadtEntryHeader = undefined;
        var i: usize = 0;
        while (i < self.header.length - @sizeOf(@This())) {
            entry = @ptrFromInt(@intFromPtr(&self.entries) + i);
            serial.println("{any}", .{entry});

            switch (entry.?.entry_type) {
                0 => {
                    const ioapic: *align(1) Madt.ProcessorLocalApic = @ptrCast(entry);
                    serial.println("{any}", .{ioapic});
                },
                1 => {
                    const ioapic: *align(1) Madt.IoApic = @ptrCast(entry);
                    serial.println("{any}", .{ioapic});
                },

                2 => {
                    const ioapic: *align(1) Madt.Iso = @ptrCast(entry);
                    serial.println("{any}", .{ioapic});
                },

                else => {},
            }

            i += @max(@sizeOf(MadtEntryHeader), entry.?.length);
        }
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
        ioapic_id: u8,
        reserved: u8,
        ioapic_addr: u32,
        gsib: u32,
    };

    pub const ProcessorLocalApic = packed struct {
        processor_id: u8,
        apic_id: u8,
        flags: u32,
    };
};

const Rsdp = extern struct {
    signature: [8]u8,
    checksum: u8,
    oem_id: [6]u8,
    revision: u8,
    rsdt: u32,
    length: u32,
    xsdt: u64,
    extend_checksum: u8,
    reserved: [3]u8,

    comptime {
        if (!(@sizeOf(Rsdp) == @sizeOf(u288))) {
            @compileError("Bad size for Rspd");
        }
    }

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

pub fn init() !void {
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
    const ioapic = try madt.?.get_ioapic();
    _ = ioapic.ioapic_addr;

    serial.println("{any}", .{ioapic});
}
