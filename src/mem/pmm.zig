const iter = @import("../iter.zig");
const ds = @import("../ds.zig");
const utils = @import("../utils.zig");
const serial = @import("../drivers/serial.zig");
const limine = @import("limine");

const Pmm = @This();

pub const PAGE_SIZE = 0x1000; // 0x1000 = 4Kib

var bitmap: ?ds.BitMapU8 = null;
var last_usable_page: u64 = 0;
var base: ?u64 = null;
var usable_size: usize = 0;

fn find_block_for_bitmap(mmap: *limine.MemoryMapResponse, bitmap_size: u64) !*limine.MemoryMapEntry {
    for (mmap.entries()) |entry| {
        if (entry.kind != limine.MemoryMapEntryType.usable) {
            continue;
        }

        if (entry.length >= bitmap_size) {
            return entry;
        }
    }
    serial.print_err("Try to allocate {} but memory size is {}", .{ bitmap_size, usable_size });
    return error.NotEnoughtMem;
}

pub fn pmm_init(mmap: *limine.MemoryMapResponse, hhdm: *limine.HhdmResponse) !void {
    base = hhdm.offset;
    var highest_addr: u64 = 0;

    for (mmap.entries()) |entry| {
        switch (entry.kind) {
            .usable => {
                const end_addr = entry.base + entry.length;

                if (end_addr > highest_addr) {
                    highest_addr = end_addr;
                }

                usable_size += entry.length;
            },
            else => {},
        }

        serial.println("MMAP - base: 0x{X}-0x{X} kind: {}", .{ entry.base, entry.base + entry.length, entry.kind });
    }

    if (highest_addr == 0) {
        @panic("No usable block");
    }

    serial.println("Usable memory size is {}", .{usable_size});

    const bitmap_size = utils.align_up(highest_addr / PAGE_SIZE / 8 + 1, PAGE_SIZE);

    var bitmap_block = try find_block_for_bitmap(mmap, bitmap_size);

    bitmap = ds.BitMapU8.new(@ptrFromInt(bitmap_block.base + hhdm.offset), bitmap_size);
    bitmap.?.init();

    bitmap_block.base += bitmap_size;
    bitmap_block.length -= bitmap_size;

    for (mmap.entries()) |entry| {
        if (entry.kind == .usable) {
            var i: u64 = entry.base;
            while (i < entry.base + entry.length) : (i += PAGE_SIZE) {
                bitmap.?.unset(i / PAGE_SIZE);
            }
        }
    }

    bitmap.?.debug();

    serial.print_ok("PMM", .{});
}

pub fn alloc(size: usize) !*void {
    // TODO: OPTIMIZATION
    const size_needed: u64 = size / PAGE_SIZE;
    var length_free_block: u64 = 0;

    for (0..bitmap.?.size) |i| {
        if (bitmap.?.get(i) == ds.State.Used) {
            length_free_block = 0;
            continue;
        }

        if (size_needed <= length_free_block) {
            bitmap.?.set_range(.{ .start = i - length_free_block, .end = i, .inclusive = true }) catch {};
            return @ptrFromInt((i - length_free_block) * PAGE_SIZE);
        }

        length_free_block += 1;
    }

    return error.NotEnoughtMem;
}

pub fn free(ptr: *void, size: usize) !void {
    const from: usize = @intFromPtr(ptr) - base.?;
    for (from..from + size) |i| {
        bitmap.?.unset(i / 4096);
    }
}

pub fn debug() void {
    bitmap.?.debug();
}

test "try_alloc" {
    var gpa = @import("std").heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const fakememorysize = PAGE_SIZE * 3;

    var entry =
        limine.MemoryMapEntry{
        .base = 0,
        .length = fakememorysize,
        .kind = .usable,
    };
    var entries = [_]*limine.MemoryMapEntry{&entry};
    var mmap = limine.MemoryMapResponse{
        .revision = 0,
        .entry_count = 1,
        .entries_ptr = &entries,
    };
    var hhdm = limine.HhdmResponse{
        .revision = 0,
        .offset = @intFromPtr(try allocator.create([fakememorysize]u8)),
    };

    try Pmm.pmm_init(
        &mmap,
        &hhdm,
    );

    try @import("std").testing.expectEqual(.Used, bitmap.?.get(0));
    try @import("std").testing.expectEqual(.Unused, bitmap.?.get(1));
    try @import("std").testing.expectEqual(.Unused, bitmap.?.get(2));
}
