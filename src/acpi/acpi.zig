const lapic = @import("../drivers/lapic.zig");
const ioapic = @import("../drivers/ioapic.zig");
const serial = @import("../drivers/serial.zig");
const pci = @import("../drivers/pci.zig");
const limine_rq = @import("../limine_rq.zig");
const std = @import("std");
const hpet = @import("../drivers/hpet.zig");
const disable_pic = @import("../drivers/pic.zig").disable_pic;

pub var rsdp: ?*align(1) Rsdp = null;
pub var rsdt: ?*align(1) Rsdt = null;

pub var madt: ?*align(1) Madt = null;
pub var xsdt: ?*align(1) Xsdt = null;
pub var mcfg: ?*align(1) Mcfg = null;

pub var cpu_count: u32 = 0;

pub const AcpiHeader = packed struct(u288) {
    signature: u32,
    /// Length in bytes
    length: u32,
    revision: u8,
    checksum: u8,
    oem_id: u48,
    oem_table_id: u64,
    oem_revision: u32,
    creator_id: u32,
    creator_revision: u32,

    const PACKED_SIZE = @bitSizeOf(AcpiHeader) / 8;

    const Self = *align(1) @This();

    inline fn get_signature_as_string(self: Self) []const u8 {
        const ptrToSliceOfChars: [*]const u8 = @ptrCast(&self.signature);
        return ptrToSliceOfChars[0..4];
    }

    fn is_signature_eq(self: *align(1) @This(), name: []const u8) bool {
        return std.mem.eql(u8, self.get_signature_as_string(), name);
    }

    comptime {
        std.testing.expectEqual(36, PACKED_SIZE) catch {
            @compileError("Size is bad");
        };
    }
};

const Xsdt = packed struct {
    header: AcpiHeader,
    end: void,

    const PACKED_SIZE = @bitSizeOf(AcpiHeader) / 8;

    pub inline fn get_nb_of_entry(self: *align(1) @This()) u64 {
        return (self.header.length - PACKED_SIZE) / @sizeOf(u64);
    }

    pub fn get(self: *align(1) @This(), name: []const u8) !*align(1) AcpiHeader {
        const hhdm_offset = limine_rq.hhdm.response.?.offset;
        const table_start = @intFromPtr(self) + PACKED_SIZE;
        const entries = @as([*]align(1) u64, @ptrFromInt(table_start))[0..self.get_nb_of_entry()];
        serial.println("Finding {s} {}", .{ name, name.len });
        for (entries) |entry| {
            const ptr: *align(1) AcpiHeader = @ptrFromInt(entry + hhdm_offset);

            serial.println("Entry with name: {s} {} {}", .{ ptr.get_signature_as_string(), ptr.get_signature_as_string().len, ptr.is_signature_eq(name) });

            if (ptr.is_signature_eq(name)) {
                return ptr;
            }
        }

        return error.EntryNotFound;
    }

    pub fn get_mcfg(self: *align(1) @This()) !*align(1) Mcfg {
        return @ptrCast(try self.get("MCFG"));
    }

    pub fn get_apic(self: *align(1) @This()) !*align(1) Madt {
        return @ptrCast(try self.get("APIC"));
    }
};

const Rsdt = packed struct(u288) {
    header: AcpiHeader,
    end: void,

    pub inline fn length(self: *align(1) @This()) u32 {
        return @divExact(self.header.length - AcpiHeader.PACKED_SIZE, @sizeOf(u32));
    }

    pub fn get(self: *align(1) @This(), name: []const u8) !*Rsdt {
        const entries = @as([*]u32, @ptrCast(@alignCast(&self.end)))[0..self.length()];
        for (entries) |entry| {
            const ptr: *Rsdt = @ptrFromInt(entry + limine_rq.hhdm.response.?.offset);

            if (ptr.header.is_signature_eq(name)) {
                return ptr;
            }
        }

        return error.NotFound;
    }

    pub fn get_apic(self: *align(1) @This()) !*align(1) Madt {
        return @ptrCast(try self.get("APIC"));
    }

    pub fn get_mcfg(self: *align(1) @This()) !*align(1) Mcfg {
        return @ptrCast(try self.get("MCFG"));
    }
};

pub const Madt = packed struct {
    header: AcpiHeader,
    lapic_addr: u32,
    flags: u32,
    entries: void,

    // REMOVE AT 0.17.0 with @backingInt()
    const PACKED_SIZE = @bitSizeOf(@This()) / 8;

    pub const MadtEntryHeader = packed struct {
        entry_type: u8,
        length: u8,
        entry: void,

        const PACKED_SIZE = @bitSizeOf(@This()) / 8;
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

    pub inline fn getEntries(self: *align(1) @This()) *void {
        return @ptrFromInt(@intFromPtr(self) + PACKED_SIZE);
    }

    pub inline fn getEnd(self: *align(1) @This()) usize {
        return @intFromPtr(self) + self.header.length;
    }

    pub fn read_entries(self: *align(1) @This()) void {
        const end: usize = self.getEnd();
        var table: usize = @intFromPtr(self.getEntries());
        var entry: *Madt.MadtEntryHeader = @ptrFromInt(table);
        while (table < end) {
            entry = @ptrFromInt(table);
            serial.println("{any}", .{entry});

            switch (entry.entry_type) {
                0 => {
                    const lapic_entry: *align(1) Madt.ProcessorLocalApic = @ptrCast(&entry.entry);
                    serial.println("{any}", .{lapic_entry});
                    cpu_count += 1;
                },
                1 => {
                    const ioapic_struct: *align(1) Madt.IoApic = @ptrCast(&entry.entry);
                    serial.println("{any}", .{ioapic_struct});
                },

                2 => {
                    const iso: *align(1) Madt.Iso = @ptrCast(entry);
                    serial.println("{any}", .{iso});
                },

                else => {
                    serial.println("UNSUPPORTED ({})", .{entry.entry_type});
                },
            }

            table += @max(MadtEntryHeader.PACKED_SIZE, entry.length);
        }

        serial.println("CPU COUNT: {}", .{cpu_count});
    }

    pub fn get_iso(self: *align(1) @This(), irq: u8) ?*align(1) Iso {
        const end: usize = self.getEnd();
        var table: usize = @intFromPtr(self.getEntries());
        var entry: *Madt.MadtEntryHeader = @ptrFromInt(table);
        while (table < end) {
            entry = @ptrFromInt(table);
            if (entry.entry_type == 2) {
                const iso: *align(1) Madt.Iso = @ptrCast(entry);
                if (iso.irq_src == irq) {
                    return iso;
                }
            }

            table += @max(MadtEntryHeader.PACKED_SIZE, entry.length);
        }

        return null;
    }

    pub fn get_ioapic(self: *align(1) @This()) !*align(1) IoApic {
        const end: usize = self.getEnd();
        var table: usize = @intFromPtr(self.getEntries());
        var entry: *Madt.MadtEntryHeader = @ptrFromInt(table);

        while (table < end) {
            entry = @ptrFromInt(table);

            if (entry.entry_type == 1) {
                return @ptrCast(entry);
            }

            table += @max(MadtEntryHeader.PACKED_SIZE, entry.length);
        }

        return error.NotFound;
    }
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

    pub inline fn get_xsdt(self: *align(1) @This()) !*align(1) Xsdt {
        if (self.revision <= 1) {
            return error.RevisionTooLow;
        }

        return @ptrFromInt(self.xsdt + limine_rq.hhdm.response.?.offset);
    }

    pub inline fn get_rsdt(self: *align(1) @This()) !*align(1) Rsdt {
        if (self.revision > 1) {
            serial.println("DEPRECATED with revision 2.\n You should use xsdt", .{});
        }

        return @ptrFromInt(@as(u64, self.rsdt) + limine_rq.hhdm.response.?.offset);
    }
};

pub const Mcfg = packed struct(u352) {
    header: AcpiHeader,
    reserved: u64,
    configuration: void,

    pub const Configuration = packed struct(u128) {
        base_addr: u64,
        pci_group: u16,
        start: u8,
        end: u8,
        reserved: u32,

        fn get_base_addr(self: @This(), addr: pci.PciAddr) u64 {
            return limine_rq.hhdm.response.?.offset + self.base_addr + (@as(u64, addr.bus_no - self.start) << 20) | (@as(u64, addr.device_no) << 15) | @as(u64, addr.fn_no) << 12 | (@as(u64, addr.offset));
        }

        pub fn read(
            self: @This(),
            addr: pci.PciAddr,
            comptime size: type,
        ) size {
            const base = self.get_base_addr(addr);
            switch (size) {
                u8, u16, u32 => {
                    return @as(*size, @ptrFromInt(base)).*;
                },
                else => {
                    @compileError("Should use u8, u16 or u32 as type");
                },
            }
        }

        pub fn write(self: @This(), addr: @import("../drivers/pci.zig").PciAddr, comptime size: type, value: size) void {
            const base = self.get_base_addr(addr);

            switch (size) {
                u8, u16, u32 => {
                    @as(*size, @ptrFromInt(base)).* = value;
                },
                else => {
                    @compileError("Should use u8, u16 or u32 as type");
                },
            }
        }
    };

    pub fn get_configuration(self: *align(1) @This()) *align(1) Configuration {
        return @ptrCast(&self.configuration);
    }

    pub fn countEntry(self: *align(1) @This()) usize {
        return (self.header.length * 8 - @bitSizeOf(Mcfg)) / @bitSizeOf(Configuration);
    }

    pub fn get_entry_of_bus(self: *align(1) @This(), bus: u8) ?*align(1) Configuration {
        const cfg: [*]align(1) Configuration = @ptrCast(&self.configuration);
        var i: usize = 0;
        while (i < self.countEntry()) : (i += 1) {
            const entry = cfg[i];
            if (entry.start <= bus and bus <= entry.end) {
                return &cfg[i];
            }
        }

        return null;
    }
};

pub fn init() !void {
    serial.println("[INIT] ACPI", .{});
    disable_pic();

    const response = limine_rq.rsdp.response orelse return error.NoRsdp;

    rsdp = @ptrFromInt(response.address);

    serial.println("[DEBUG] Rsdp: {any}", .{rsdp});
    serial.println("[DEBUG] RSDP Revision: {}", .{rsdp.?.revision});

    if (rsdp.?.revision > 1) {
        xsdt = try rsdp.?.get_xsdt();
        serial.println("XSPT: {any}", .{xsdt});

        madt = try xsdt.?.get_apic();

        serial.println("MADT: {any}", .{madt});
        mcfg = try xsdt.?.get_mcfg();
    } else {
        rsdt = try rsdp.?.get_rsdt();
        serial.println("{any}", .{rsdt});

        madt = try rsdt.?.get_apic();
        mcfg = try rsdt.?.get_mcfg();
    }

    serial.println("Try to read entries", .{});

    madt.?.read_entries();

    try lapic.init();
    try hpet.init();

    var io_apic = (try madt.?.get_ioapic()).ioapic;
    io_apic.init();

    lapic.init_timer();
}
