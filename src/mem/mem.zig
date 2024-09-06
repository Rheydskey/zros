const limine_rq = @import("../limine_rq.zig");
pub const utils = @import("../utils.zig");

pub fn mmap_virt_to_phys(virt: usize) usize {
    return virt - limine_rq.hhdm.response.?.offset;
}

pub fn mmap_phys_to_virt_ptr(phys: *anyopaque) *anyopaque {
    return @ptrFromInt(mmap_phys_to_virt(@intFromPtr(phys)));
}

pub fn mmap_phys_to_virt(phys: usize) usize {
    return phys + limine_rq.hhdm.response.?.offset;
}

pub fn mmap_phys_to_kernel(phys: anytype) usize {
    return limine_rq.kaddr_req.response.?.virtual_base + @intFromPtr(phys);
}

// Inspiration of rust's x86_64 crate

pub const VirtAddr = struct {
    addr: u64,

    pub fn new(addr: u64) !VirtAddr {
        const virtaddr: VirtAddr = new_truncate(addr);

        if (virtaddr.addr != addr) return error.BadVirtAddr;

        return virtaddr;
    }

    pub fn new_truncate(addr: u64) VirtAddr {
        return .{ .addr = @bitCast(@as(i64, @bitCast(addr << 16)) >> 16) };
    }

    pub fn as_u48(self: *const VirtAddr) u48 {
        return @truncate(self.addr);
    }

    inline fn get_index_of_pml(addr: u64, comptime level: u8) u64 {
        const shift: u64 = 12 + level * 9;
        return (addr & (0x1ff << shift)) >> shift;
    }

    pub fn get_pml4_index(self: *const VirtAddr) u64 {
        return get_index_of_pml(self.addr, 3);
    }

    pub fn get_pml3_index(self: *const VirtAddr) u64 {
        return get_index_of_pml(self.addr, 2);
    }

    pub fn get_pml2_index(self: *const VirtAddr) u64 {
        return get_index_of_pml(self.addr, 1);
    }

    pub fn get_pml1_index(self: *const VirtAddr) u64 {
        return get_index_of_pml(self.addr, 0);
    }

    pub fn align_up(self: *const VirtAddr, alignment: u64) !VirtAddr {
        return VirtAddr.new(utils.align_up(self.addr, alignment));
    }

    pub fn align_down(self: *const VirtAddr, alignment: u64) !VirtAddr {
        return VirtAddr.new(utils.align_down(self.addr, alignment));
    }
};

test "pml_index" {
    const assert = @import("std").debug.assert;
    const virt = VirtAddr.new_truncate(0xff7f80005000);

    assert(virt.get_pml4_index() == 510);
    assert(virt.get_pml3_index() == 510);
    assert(virt.get_pml2_index() == 0);
    assert(virt.get_pml1_index() == 5);
}

pub const PhysAddr = struct {
    addr: u64,

    pub fn new(addr: u64) !PhysAddr {
        const phys: PhysAddr = .{ .addr = addr % (1 << 52) };

        if (phys.addr != addr) return error.BadPhysAddr;

        return phys;
    }

    pub fn as_u52(self: *const PhysAddr) u52 {
        return @truncate(self.addr);
    }

    pub fn align_up(self: *const PhysAddr, alignment: u64) !PhysAddr {
        return PhysAddr.new(utils.align_up(self.addr, alignment));
    }

    pub fn align_down(self: *const PhysAddr, alignment: u64) !PhysAddr {
        return PhysAddr.new(utils.align_down(self.addr, alignment));
    }

    pub fn to_virt(self: *const PhysAddr) VirtAddr {
        return self.try_to_virt() catch |err| {
            @import("std").debug.panic("Cannot convert to virt. Addr: {} Error {}", .{ self.addr, err });
        };
    }

    pub fn to_kernel(self: *const PhysAddr) VirtAddr {
        return self.try_to_kernel() catch |err| {
            @import("std").debug.panic("Cannot convert to kernel. Addr: {} Error {}", .{ self.addr, err });
        };
    }

    pub fn try_to_virt(self: *const PhysAddr) !VirtAddr {
        return VirtAddr.new(self.addr + limine_rq.hhdm.response.?.offset);
    }

    pub fn try_to_kernel(self: *const PhysAddr) !VirtAddr {
        return VirtAddr.new(self.addr + limine_rq.kaddr_req.response.?.virtual_base);
    }
};
