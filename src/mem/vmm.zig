const assert = @import("std").debug.assert;
const serial = @import("../drivers/serial.zig");
const limine = @import("limine");
const limine_rq = @import("../limine_rq.zig");
const pmm = @import("pmm.zig");
const utils = @import("../utils.zig");

const VMM_ADDR_MASK: u64 = 0x000ffffffffff000;

extern const text_start_addr: [*]u8;
extern const text_end_addr: [*]u8;

extern const rodata_start_addr: u64;
extern const rodata_end_addr: u64;

extern const data_start_addr: u64;
extern const data_end_addr: u64;

var kernel_pml4: *Pml = undefined;

const PmlE = packed union { raw: u64, entry: PmlEntry };

const PmlEntryFlag = struct {
    const PRESENT = (1 << 0);
    const READ_WRITE = (1 << 1);
    const USER = (1 << 2);
    const PAGE_WRITH_THROUGH = (1 << 3);
    const CACHING_DISABLE = (1 << 4);
    const ACCESSED = (1 << 5);
    const DIRTY = (1 << 6);
    const HUGE_PAGE = (1 << 7);
    const GLOBAL_PAGE = (1 << 8);
    const NOX = (1 << 63);
};

const PmlEntry = packed struct(u64) {
    flags: u9 = PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE,
    available: u3 = 0,
    physical: u52 = 0,

    pub fn new_with_addr(addr: u64) @This() {
        return .{ .physical = @truncate(addr >> 12) };
    }
};

const Pml = struct { entries: [512]PmlE };

inline fn PMLX_get_index(addr: u64, level: u8) u64 {
    const shift: u64 = 12 + level * 9;
    return (addr & (0x1ff << shift)) >> shift;
}

fn get_pml4_index(addr: u64) u64 {
    return PMLX_get_index(addr, 3);
}

fn get_pml3_index(addr: u64) u64 {
    return PMLX_get_index(addr, 2);
}

fn get_pml2_index(addr: u64) u64 {
    return PMLX_get_index(addr, 1);
}

fn get_pml1_index(addr: u64) u64 {
    return PMLX_get_index(addr, 0);
}

pub fn addHhdmToPtr(ptr: *void, hhdm: *limine.HhdmResponse) *void {
    return @ptrFromInt(@intFromPtr(ptr) + hhdm.offset);
}

pub fn init(hhdm: *limine.HhdmResponse) !void {
    serial.println("VMM init", .{});
    serial.println("HHDM: 0x{x} KADDR: 0x{x}", .{ hhdm.*.offset, limine_rq.kaddr_req.response.?.virtual_base });

    const alloc_page = pmm.alloc(pmm.PAGE_SIZE) catch {
        return;
    };

    @memset(@as(*[pmm.PAGE_SIZE]u8, @ptrCast(addHhdmToPtr(alloc_page, hhdm))), 0);

    kernel_pml4 = @ptrFromInt(@intFromPtr(alloc_page) + hhdm.offset);

    for (256..512) |i| {
        _ = get_next_level(kernel_pml4, i) catch {
            @panic("ouppps");
        };
    }

    try map_section_range(@intFromPtr(&text_start_addr), @intFromPtr(&text_end_addr), PmlEntryFlag.PRESENT);
    try map_section_range(@intFromPtr(&data_start_addr), @intFromPtr(&data_end_addr), PmlEntryFlag.PRESENT | PmlEntryFlag.NOX | PmlEntryFlag.READ_WRITE);
    try map_section_range(@intFromPtr(&rodata_start_addr), @intFromPtr(&rodata_end_addr), PmlEntryFlag.PRESENT | PmlEntryFlag.NOX);

    var addr: u64 = pmm.PAGE_SIZE;
    while (addr < 0x100000000) : (addr += pmm.PAGE_SIZE) {
        try alloc(kernel_pml4, addr, addr, PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE);
        try alloc(kernel_pml4, addr + hhdm.offset, addr, PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE | PmlEntryFlag.NOX);
    }

    const memmap = limine_rq.memory_map.response.?;

    for (0..memmap.entry_count) |i| {
        const entry = memmap.entries()[i];
        const base = utils.align_down(entry.base, pmm.PAGE_SIZE);
        const top = utils.align_up(entry.base + entry.length, pmm.PAGE_SIZE);

        if (top <= 0x100_000_000) {
            continue;
        }

        var j: u64 = base;

        while (j < top) : (j += pmm.PAGE_SIZE) {
            if (j < 0x100_000_00) {
                continue;
            }

            try alloc(kernel_pml4, j, j, PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE);
            try alloc(kernel_pml4, j + hhdm.offset, j, PmlEntryFlag.PRESENT | PmlEntryFlag.READ_WRITE | PmlEntryFlag.NOX);
        }
    }
    serial.println("Switch pagemap", .{});
    switch_to_pagemap(@intFromPtr(kernel_pml4) - hhdm.offset);
}

fn get_next_level(pml: *Pml, index: u64) !*Pml {
    const page: PmlE = pml.*.entries[index];
    if (page.entry.flags & PmlEntryFlag.PRESENT != 0) {
        return @ptrFromInt((page.raw & VMM_ADDR_MASK) + limine_rq.hhdm.response.?.offset);
    } else {
        const alloc_page = try pmm.alloc(1);
        var pml_entry =
            PmlEntry.new_with_addr(@intFromPtr(alloc_page));

        pml_entry.flags |= PmlEntryFlag.USER;
        @memset(@as(*[4096]u8, @ptrCast(addHhdmToPtr(alloc_page, limine_rq.hhdm.response.?))), 0);
        pml.entries[index] = PmlE{ .entry = pml_entry };

        return @ptrFromInt(@intFromPtr(alloc_page) + limine_rq.hhdm.response.?.offset);
    }
}

fn alloc(pml: *Pml, virt: u64, phys: u64, flags: u64) !void {
    const pml4_index = get_pml4_index(virt);
    const pml3_index = get_pml3_index(virt);
    const pml2_index = get_pml2_index(virt);
    const pml1_index = get_pml1_index(virt);

    const pml3 = try get_next_level(pml, pml4_index);
    const pml2 = try get_next_level(pml3, pml3_index);
    const pml1 = try get_next_level(pml2, pml2_index);

    pml1.entries[pml1_index] = PmlE{ .entry = PmlEntry.new_with_addr(phys) };
    pml1.entries[pml1_index].raw |= flags;
}

fn map_section_range(start_addr: u64, end_addr: u64, flags: u64) !void {
    var text_addr = utils.align_down(start_addr, pmm.PAGE_SIZE);
    while (text_addr < utils.align_up(end_addr, pmm.PAGE_SIZE)) : (text_addr += pmm.PAGE_SIZE) {
        const kaddr = limine_rq.kaddr_req.response.?;
        const physical: usize = text_addr - kaddr.virtual_base + kaddr.physical_base;
        try alloc(kernel_pml4, text_addr, physical, flags);
    }
}

fn free(_: u64) !void {
    @panic("TODO: FREE");
}

fn switch_to_pagemap(pagemap: u64) void {
    asm volatile ("mov %[value], %%cr3"
        :
        : [value] "{rax}" (pagemap),
    );
}
