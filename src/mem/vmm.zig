const assert = @import("std").debug.assert;
const serial = @import("../drivers/serial.zig");
const limine = @import("limine");
const limine_rq = @import("../limine_rq.zig");
const pmm = @import("pmm.zig");
const utils = @import("../utils.zig");
const mem = @import("mem.zig");

const VMM_ADDR_MASK: u64 = 0x000ffffffffff000;
const MAX_MEMORY: u64 = 0x100_000_000;

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

    pub fn to_int(self: *const PmlEntryFlag) u9 {
        return @bitCast(self.*);
    }

    pub const PRESENT = (1 << 0);
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
        return .{ .physical = (try mem.PhysAddr.new(addr)).as_u52() };
    }

    pub fn as_u64(self: *const PmlEntry) u64 {
        return @bitCast(self.*);
    }
};

const Pml = struct { entries: [512]PmlEntry = undefined };

pub fn init(memmap: *limine.MemoryMapResponse) !void {
    serial.println("VMM init", .{});

    const alloc_page = try pmm.alloc(pmm.PAGE_SIZE);

    serial.println("===== aHJhahaha : {p}", .{alloc_page});

    kernel_pml4 = @alignCast(@ptrCast(mem.mmap_phys_to_virt_ptr(alloc_page)));
    @memset(@as(*[pmm.PAGE_SIZE]u8, @ptrCast(kernel_pml4)), 0);

    serial.println("HEERREEE", .{});

    for (256..512) |i| {
        _ = get_next_level(kernel_pml4.?, i) catch {
            @panic("ouppps");
        };
    }

    serial.println("HEERREEE", .{});

    try map_kernel();

    serial.println("HEERREEE", .{});

    //    debug(kernel_pml4.?);

    var addr: u64 = pmm.PAGE_SIZE;

    while (addr < MAX_MEMORY) : (addr += pmm.PAGE_SIZE) {
        try alloc(kernel_pml4.?, addr, addr, PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE);
        try alloc(kernel_pml4.?, mem.mmap_phys_to_virt(addr), addr, PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE | PmlEntryFlag.NOX);
    }

    for (0..memmap.entry_count) |i| {
        const entry = memmap.entries()[i];
        const base = try (try mem.PhysAddr.new(entry.base)).align_down(pmm.PAGE_SIZE);
        const top = try (try mem.PhysAddr.new(entry.base + entry.length)).align_up(pmm.PAGE_SIZE);

        if (top.addr <= MAX_MEMORY) {
            continue;
        }

        var j: u64 = base.addr;

        while (j < top.addr) : (j += pmm.PAGE_SIZE) {
            if (j < 0x10_000_000) {
                continue;
            }

            try alloc(kernel_pml4.?, j, j, PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE);
            try alloc(kernel_pml4.?, mem.mmap_phys_to_virt(j), j, PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE | PmlEntryFlag.NOX);
        }
    }

    //  debug(kernel_pml4.?);
    serial.println("Switch pagemap", .{});
    //    switch_to_pagemap(mem.mmap_virt_to_phys(@intFromPtr(kernel_pml4.?)));
}

fn debug(pml: *Pml) void {
    for (pml.entries, 0..) |entry, i| {
        serial.println("At {} => {any}", .{ i, entry.entry });
    }
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
    serial.println("Check for {}", .{index});

    const page: PmlEntry = pml.*.entries[index];

    if (page.flags.present) {
        serial.println("Present", .{});
        return @ptrFromInt((page.as_u64() & VMM_ADDR_MASK) + limine_rq.hhdm.response.?.offset);
    }

    serial.println("Not present", .{});

    const alloc_page = try pmm.alloc(1);

    serial.println("get a page", .{});
    var pml_entry =
        try PmlEntry.new_with_addr(@intFromPtr(alloc_page));

    serial.println("new", .{});

    pml_entry.flags.user = true;

    serial.println("set flags", .{});
    @memset(@as(*[4096]u8, @ptrCast(mem.mmap_phys_to_virt_ptr(alloc_page))), 0);

    serial.println("memsetted", .{});
    pml.entries[index] = pml_entry;

    return @ptrCast(mem.mmap_phys_to_virt_ptr(alloc_page));
}

pub fn alloc(pml: *Pml, virt: u64, phys: u64, flags: u64) !void {
    const virt_addr = try mem.VirtAddr.new(virt);

    const pml4_index = virt_addr.get_pml4_index();
    const pml3_index = virt_addr.get_pml3_index();
    const pml2_index = virt_addr.get_pml2_index();
    const pml1_index = virt_addr.get_pml1_index();

    serial.println("H", .{});

    const pml3 = try get_next_level(pml, pml4_index);
    const pml2 = try get_next_level(pml3, pml3_index);
    const pml1 = try get_next_level(pml2, pml2_index);

    serial.println("H", .{});

    pml1.entries[pml1_index] = try PmlEntry.new_with_addr(phys);
    pml1.entries[pml1_index] = @bitCast(@as(u64, @bitCast(pml1.entries[pml1_index])) | flags);
}

fn map_section_range(start_addr: u64, end_addr: u64, flags: u64) !void {
    var addr = utils.align_down(start_addr, pmm.PAGE_SIZE);

    serial.println("oi oi", .{});

    while (addr < utils.align_up(end_addr, pmm.PAGE_SIZE)) : (addr += pmm.PAGE_SIZE) {
        const kaddr = limine_rq.kaddr_req.response.?;
        const physical: usize = addr - kaddr.virtual_base + kaddr.physical_base;

        serial.println("oi oi: {X}", .{addr});

        try alloc(kernel_pml4.?, addr, physical, flags);
    }
}

fn free(pml: *Pml, virt: u64) !void {
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

fn inittest() !u64 {
    var gpa = @import("std").heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const fakememorysize = pmm.PAGE_SIZE * 0x100;

    const memory = try allocator.alloc(u8, fakememorysize);
    @memset(memory, 0);
    // defer allocator.free(memory);

    var entry =
        limine.MemoryMapEntry{
        .base = 0,
        .length = @intFromPtr(&memory),
        .kind = .reserved,
    };

    var usable =
        limine.MemoryMapEntry{
        .base = @intFromPtr(&memory),
        .length = @intFromPtr(&memory) + fakememorysize,
        .kind = .usable,
    };

    var entries = [_]*limine.MemoryMapEntry{ &entry, &usable };
    var mmap = limine.MemoryMapResponse{
        .revision = 0,
        .entry_count = 2,
        .entries_ptr = &entries,
    };

    limine_rq.memory_map.response = &mmap;

    var hhdm = limine.HhdmResponse{
        .revision = 0,
        .offset = 0,
    };

    limine_rq.hhdm.response = &hhdm;

    var k = limine.KernelAddressResponse{ .physical_base = 0, .virtual_base = 0, .revision = 0 };

    limine_rq.kaddr_req.response = &k;

    try pmm.pmm_init(
        &mmap,
        &hhdm,
    );

    try init(&hhdm, &mmap);

    return hhdm.offset;
}

test {
    _ = try inittest();

    try alloc(kernel_pml4.?, 0xfff_000_000, 0x7000, PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE | PmlEntryFlag.USER);
}
