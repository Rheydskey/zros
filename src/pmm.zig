const ds = @import("./ds.zig");
const utils = @import("./utils.zig");
const serial = @import("./serial.zig");
const limine = @import("limine");

const MMAP_IO_BASE = 0xffff800000000000;
const MMAP_IO_KERNEL = 0xffffffff80000000;

const PAGE_SIZE = 0x1000; // 0x1000 = 4Kb

var bitmap: ?ds.BitMapU8 = null;

pub fn get_size_of_bitmap(length: usize) usize {
    return utils.align_up(length / PAGE_SIZE / 8, PAGE_SIZE);
}

pub fn pmm_init(mmap: *limine.MemoryMapResponse) void {
    const entries = mmap.entries();
    const first = entries[0];
    const last = entries[entries.len - 1];
    var first_usable: ?*limine.MemoryMapEntry = null;

    const bm_length = utils.align_up((last.length - first.base) / PAGE_SIZE / 8, PAGE_SIZE);
    serial.println("Will alloc {}", .{bm_length});
    for (entries) |entry| {
        if (first_usable == null and entry.kind == limine.MemoryMapEntryType.usable and entry.length >= bm_length) {
            first_usable = entry;
        }

        serial.println("MMAP - base: 0x{X}-0x{X} kind: {}", .{ entry.base, entry.base + entry.length, entry.kind });
    }

    if (first_usable == null) {
        @panic("No usable block");
    }

    serial.println("base: {x}, lenght: {x}", .{ first.base, last.base + last.length });

    bitmap = ds.BitMapU8.new(@ptrFromInt(first_usable.?.base + MMAP_IO_BASE), bm_length);
    bitmap.?.init();
}
