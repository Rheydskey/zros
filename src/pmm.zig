const ds = @import("./ds.zig");
const utils = @import("./utils.zig");

const PAGE_SIZE = 0x1000; // 0x1000 = 4Kb

var bitmap: ?ds.BitMapU8 = null;

pub fn pmm_init(addr: *void, length: usize) void {
    bitmap = ds.BitMapU8.new(addr, utils.align_up(length / PAGE_SIZE / 8, PAGE_SIZE));
    bitmap.?.debug();
}
