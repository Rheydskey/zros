const iter = @import("iter.zig");
const ds = @import("./ds.zig");
const utils = @import("./utils.zig");
const serial = @import("./serial.zig");
const limine = @import("limine");

const PAGE_SIZE = 0x1000; // 0x1000 = 4Kb

var bitmap: ?ds.BitMapU8 = null;

fn get_usable_range(mmap: *limine.MemoryMapResponse) iter.Range {
    var usable_range: iter.Range = .{
        .start = 0,
        .end = 0,
        .inclusive = false,
    };

    for (mmap.entries()) |entry| {
        if (entry.kind == limine.MemoryMapEntryType.usable) {
            if (entry.base + entry.length > usable_range.end) {
                usable_range.end = entry.base + entry.length;
            }

            if (entry.base < usable_range.start) {
                usable_range.start = entry.base;
            }
        }
    }

    return usable_range;
}

pub fn get_size_of_bitmap(length: usize) usize {
    return utils.align_up(length / PAGE_SIZE / 8, PAGE_SIZE);
}

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
        switch (entry.kind) {
            .usable => {
                const range: iter.Range = .{
                    .start = entry.base / PAGE_SIZE,
                    .end = (entry.base + entry.length) / PAGE_SIZE,
                    .inclusive = false,
                };

                serial.println("Start: 0x{X}, end: 0x{X}", .{ range.start, range.end });

                bitmap.?.unset_range(range) catch {
                    @panic("Cannot unset");
                };
            },
            else => {},
        }
    }

    bitmap.?.debug();
}
