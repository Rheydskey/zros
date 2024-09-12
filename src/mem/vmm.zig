const assert = @import("std").debug.assert;
const serial = @import("../drivers/serial.zig");
const limine = @import("limine");
const limine_rq = @import("../limine_rq.zig");
const pmm = @import("pmm.zig");
const utils = @import("../utils.zig");
const mem = @import("mem.zig");

const Section = struct {
    extern const text_start_addr: [*]u8;
    extern const text_end_addr: u64;

    extern const rodata_start_addr: [*]u8;
    extern const rodata_end_addr: u64;

    extern const data_start_addr: [*]u8;
    extern const data_end_addr: u64;
};

pub var kernel_pml4: ?*Pml = null;

pub const PmlEntryFlag = packed struct(u9) {
    present: bool,
    read_write: bool,
    user: bool,
    page_write_through: bool,
    caching_disable: bool,
    accessed: bool,
    dirty: bool,
    huge_page: bool,
    global_page: bool,

    pub fn from(flags: u9) PmlEntryFlag {
        return @bitCast(flags);
    }

    pub fn from_u64(flags: u64) PmlEntryFlag {
        return from(@truncate(flags));
    }

    pub fn to_int(self: *const PmlEntryFlag) u9 {
        return @bitCast(self.*);
    }

    pub const PRESENT = 1;
    pub const READ_WRITE = (1 << 1);
    pub const USER = (1 << 2);
    pub const PAGE_WRITE_THROUGH = (1 << 3);
    pub const CACHING_DISABLE = (1 << 4);
    pub const ACCESSED = (1 << 5);
    pub const DIRTY = (1 << 6);
    pub const HUGE_PAGE = (1 << 7);
    pub const GLOBAL_PAGE = (1 << 8);
    pub const NOX = (1 << 63);
};

const PmlEntry = packed struct(u64) {
    flags: PmlEntryFlag = PmlEntryFlag.from(PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE),
    available: u3 = 0,
    physical: u52 = 0,

    pub fn new_with_addr(addr: u64) !@This() {
        if (!mem.utils.is_align(addr, pmm.PAGE_SIZE)) return error.AddrNotAligned;
        return .{ .physical = @truncate(addr >> 12) };
    }

    pub fn set_flags(self: *PmlEntry, flags: PmlEntryFlag) void {
        self.flags = flags;
    }

    pub fn as_u64(self: *const PmlEntry) u64 {
        return @bitCast(self.*);
    }

    pub fn as_phys_addr(self: *align(1) const PmlEntry) !mem.PhysAddr {
        return mem.PhysAddr.new(self.physical << 12);
    }
};

const Pml = struct { entries: [512]PmlEntry = undefined };

comptime {
    @import("../utils.zig").checkSize(Pml, 4096);
}

pub fn init(memmap: *limine.MemoryMapResponse) !void {
    serial.println("VMM init", .{});

    const alloc_page = try pmm.alloc(pmm.PAGE_SIZE);

    serial.println("===== aHJhahaha : {p}", .{alloc_page});

    kernel_pml4 = @alignCast(@ptrCast(mem.mmap_phys_to_virt_ptr(alloc_page)));
    @memset(@as(*[pmm.PAGE_SIZE]u8, @ptrCast(kernel_pml4)), 0);

    for (256..512) |i| {
        _ = get_next_level(kernel_pml4.?, i) catch |err| {
            @import("std").debug.panic("ouppps: {}", .{err});
        };
    }

    try map_kernel();

    var addr: u64 = 0;
    // Map the first 4gb
    while (addr < 0x100000000) : (addr += pmm.PAGE_SIZE) {
        try map_page(kernel_pml4.?, addr, addr, PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE | PmlEntryFlag.USER);
        try map_page(kernel_pml4.?, mem.mmap_phys_to_virt(addr), addr, PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE);
    }

    for (0..memmap.entry_count) |i| {
        const entry = memmap.entries()[i];
        if (entry.kind == .kernel_and_modules) {
            const phys = try mem.PhysAddr.new(entry.base);

            try map_page(kernel_pml4.?, phys.to_kernel().addr, phys.addr, PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE);

            continue;
        }

        const base = try (try mem.PhysAddr.new(entry.base)).align_down(pmm.PAGE_SIZE);
        const top = try (try mem.PhysAddr.new(entry.base + entry.length)).align_up(pmm.PAGE_SIZE);

        // 4GiB = 0x100_000_000
        // map only over 4GiB cause 0..4Gib is already mapped
        if (base.addr >= 0x100_000_000) {
            var j: u64 = base.addr;
            while (j < top.addr) : (j += pmm.PAGE_SIZE) {
                const phys = try mem.PhysAddr.new(j);
                try map_page(kernel_pml4.?, phys.to_virt().addr, phys.addr, PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE);
            }
        }
    }

    serial.println("Switch pagemap", .{});
    switch_to_pagemap(mem.mmap_virt_to_phys(@intFromPtr(kernel_pml4.?)));
}

fn map_kernel() !void {
    if (@import("builtin").is_test) {
        return;
    }

    try map_section_range(@intFromPtr(&Section.text_start_addr), @intFromPtr(&Section.text_end_addr), PmlEntryFlag.PRESENT);
    try map_section_range(@intFromPtr(&Section.data_start_addr), @intFromPtr(&Section.data_end_addr), PmlEntryFlag.PRESENT | PmlEntryFlag.NOX | PmlEntryFlag.READ_WRITE);
    try map_section_range(@intFromPtr(&Section.rodata_start_addr), @intFromPtr(&Section.rodata_end_addr), PmlEntryFlag.PRESENT | PmlEntryFlag.NOX);
}

fn get_next_level(pml: *align(1) Pml, index: u64) !*align(1) Pml {
    const page: PmlEntry = pml.*.entries[index];

    if (page.flags.present) {
        const phys = try page.as_phys_addr();

        return @ptrFromInt(phys.to_virt().addr);
    }

    const alloc_page = try pmm.alloc(1);

    const pml_entry =
        try PmlEntry.new_with_addr(@intFromPtr(alloc_page));
    @memset(@as(*[4096]u8, @ptrCast(mem.mmap_phys_to_virt_ptr(alloc_page))), 0);
    pml.entries[index] = pml_entry;

    return @ptrCast(mem.mmap_phys_to_virt_ptr(alloc_page));
}

pub fn map_page(pml: *Pml, virt: u64, phys: u64, flags: u64) !void {
    const virt_addr = try mem.VirtAddr.new(virt);

    const pml4_index = virt_addr.get_pml4_index();
    const pml3_index = virt_addr.get_pml3_index();
    const pml2_index = virt_addr.get_pml2_index();
    const pml1_index = virt_addr.get_pml1_index();

    const pml3 = try get_next_level(pml, pml4_index);
    const pml2 = try get_next_level(pml3, pml3_index);
    const pml1 = try get_next_level(pml2, pml2_index);

    if (pml1.entries[pml1_index].flags.present) {
        serial.println("{X} is already map to {X}", .{ virt, (try pml1.entries[pml1_index].as_phys_addr()).addr });
        return error.AlreadyMap;
    }

    var entry = try PmlEntry.new_with_addr(phys);
    entry.set_flags(PmlEntryFlag.from_u64(flags));

    pml1.entries[pml1_index] = entry;
}

pub fn remap_page(pml: *Pml, virt: u64, phys: u64, flags: u64) !void {
    const virt_addr = try mem.VirtAddr.new(virt);

    const pml4_index = virt_addr.get_pml4_index();
    const pml3_index = virt_addr.get_pml3_index();
    const pml2_index = virt_addr.get_pml2_index();
    const pml1_index = virt_addr.get_pml1_index();

    const pml3 = try get_next_level(pml, pml4_index);
    const pml2 = try get_next_level(pml3, pml3_index);
    const pml1 = try get_next_level(pml2, pml2_index);

    var entry = try PmlEntry.new_with_addr(phys);
    entry.set_flags(PmlEntryFlag.from_u64(flags));

    serial.println("{any}", .{entry});
    serial.println("{X}", .{@as(u64, @bitCast(entry))});

    pml1.entries[pml1_index] = entry;

    asm volatile ("invlpg (%[addr])"
        :
        : [addr] "r" (virt),
        : "memory"
    );
}

fn map_section_range(start_addr: u64, end_addr: u64, flags: u64) !void {
    var addr = utils.align_down(start_addr, pmm.PAGE_SIZE);

    while (addr < utils.align_up(end_addr, pmm.PAGE_SIZE)) : (addr += pmm.PAGE_SIZE) {
        const kaddr = limine_rq.kaddr_req.response.?;
        const physical: usize = addr - kaddr.virtual_base + kaddr.physical_base;

        try map_page(kernel_pml4.?, addr, physical, flags);
    }
}

fn unmap_page(pml: *Pml, virt: u64) !void {
    const virt_addr = try mem.VirtAddr.new(virt);

    const pml4_index = virt_addr.get_pml4_index();
    const pml3_index = virt_addr.get_pml3_index();
    const pml2_index = virt_addr.get_pml2_index();
    const pml1_index = virt_addr.get_pml1_index();

    const pml3 = try get_next_level(pml, pml4_index);
    const pml2 = try get_next_level(pml3, pml3_index);
    const pml1 = try get_next_level(pml2, pml2_index);

    pml1.entries[pml1_index].entry = .{ .flags = @bitCast(0) };
}

fn switch_to_pagemap(pagemap: u64) void {
    if (@import("builtin").is_test) {
        return;
    }

    const registers = @import("../arch/x86/regs.zig");

    var cr3: registers.Cr3 = .{};
    cr3.write_page_base(pagemap);
    serial.println("New CR3: {any}", .{cr3});
    cr3.apply();
}
