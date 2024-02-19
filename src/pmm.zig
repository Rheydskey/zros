const iter = @import("iter.zig");
const ds = @import("./ds.zig");
const utils = @import("./utils.zig");
const serial = @import("./serial.zig");
const limine = @import("limine");

const PAGE_SIZE = 0x1000; // 0x1000 = 4Kb

pub var bitmap: ?ds.BitMapU8 = null;
pub var last_usable_page: u64 = 0;
pub var base: ?u64 = null;

fn find_block_for_bitmap(mmap: *limine.MemoryMapResponse, bitmap_size: u64) ?*limine.MemoryMapEntry {
    for (mmap.entries()) |entry| {
        if (entry.kind != limine.MemoryMapEntryType.usable) {
            continue;
        }

        if (entry.length >= bitmap_size) {
            return entry;
        }
    }

    return null;
}

pub fn pmm_init(mmap: *limine.MemoryMapResponse, hhdm: *limine.HhdmResponse) void {
    base = hhdm.offset;
    const entries = mmap.entries();
    var highest_addr: u64 = 0;
    var usable_size: usize = 0;

    for (entries) |entry| {
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

    const bitmap_size = utils.align_up(highest_addr / PAGE_SIZE / 8, PAGE_SIZE);

    var bitmap_block = find_block_for_bitmap(mmap, bitmap_size).?;

    bitmap = ds.BitMapU8.new(@ptrFromInt(bitmap_block.base + hhdm.offset), bitmap_size);
    bitmap.?.init();

    bitmap_block.base += bitmap_size;
    bitmap_block.length -= bitmap_size;

    for (entries) |entry| {
        if (entry.kind == .usable) {
            serial.println("MMAP - base: 0x{X}-0x{X} kind: {}", .{ entry.base, entry.base + entry.length, entry.kind });
            var i: u64 = entry.base;
            while (i < entry.base + entry.length) {
                bitmap.?.unset(i / PAGE_SIZE);

                i += PAGE_SIZE;
            }
        }
    }

    bitmap.?.debug();

    serial.println("[ OK ] PMM", .{});
}

pub fn alloc(size: usize) ?*void {
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
            return @ptrFromInt(base.? + (i - length_free_block) * PAGE_SIZE);
        }

        length_free_block += 1;
    }

    return null;
}

pub fn free(ptr: *void, size: usize) !void {
    const from: usize = @intFromPtr(ptr) - base.?;
    for (from..from + size) |i| {
        bitmap.?.unset(i / 4096);
    }
}
