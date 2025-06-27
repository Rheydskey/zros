const kheap = @import("../main.zig").kheap.?;

const mem = @import("./mem.zig");
const vmm = @import("./vmm.zig");

pub const Mmio = struct {
    phys_addr: usize,
    virt_addr: usize,

    // Number of page
    len: usize,

    /// Len is the number of page
    pub fn fromPhys(phys_addr: usize, len: usize) Mmio {
        vmm.remap_range(vmm.kernel_pml4.?, mem.mmap_phys_to_virt(phys_addr), phys_addr, vmm.PmlEntryFlag.CACHING_DISABLE | vmm.PmlEntryFlag.READ_WRITE | vmm.PmlEntryFlag.PRESENT, len) catch |e| {
            @import("../drivers/serial.zig").println("{}", .{e});

            @panic("eee");
        };

        return .{
            .phys_addr = phys_addr,
            .virt_addr = mem.mmap_phys_to_virt(phys_addr),
            .len = len,
        };
    }
};
