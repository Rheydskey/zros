const serial = @import("serial.zig");
const limine = @import("limine");
const limine_rq = @import("./limine_rq.zig");
const std = @import("std");

pub var rspt: ?*Rspt = undefined;
pub var rspd: ?*Rspd = undefined;

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

const Rspt = extern struct {
    header: AcpiSDT,
    stdAddr: [0]u32,

    pub inline fn length(self: *@This()) u32 {
        return @divExact(self.header.length - @sizeOf(AcpiSDT), @sizeOf(u32));
    }

    pub fn get(self: *@This(), name: *const []const u8) !*Rspt {
        const entries = @as([*]u32, &self.stdAddr)[0..self.length()];
        for (entries) |entry| {
            const ptr: *Rspt = @ptrFromInt(entry + limine_rq.hhdm.response.?.offset);

            if (std.mem.eql(u8, &ptr.header.signature, name.*)) {
                return ptr;
            }
        }

        return error.NotFound;
    }

    pub fn get_apic(self: *@This()) !*Madt {
        const madt = try self.get(&"APIC");
        return @ptrCast(madt);
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
};

const Rspd = extern struct {
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
        if (!(@sizeOf(Rspd) == @sizeOf(u288))) {
            @compileError("Bad size for Rspd");
        }
    }

    pub inline fn get_xsdt(self: *@This()) !void {
        if (self.revision <= 1) {
            return error.RevisionTooLow;
        }
    }

    pub inline fn get_rsdt(self: *@This()) !*Rspt {
        return @ptrFromInt(@as(u64, self.rsdt) + limine_rq.hhdm.response.?.offset);
    }
};

pub fn get_rspd() !*Rspd {
    const response = limine_rq.rspd.response orelse return error.NoRspd;
    return @alignCast(@ptrCast(response.address));
}

pub fn init() !void {
    const response = limine_rq.rspd.response orelse return error.NoRspd;
    rspd = @alignCast(@ptrCast(response.address));
    rspt = try rspd.?.get_rsdt();
}
