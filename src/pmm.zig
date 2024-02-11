const ds = @import("./ds.zig");

const PAGE_SIZE = 0x1000; // 0x1000 = 4Kb

var bitmap: bitmap = undefined;

pub fn pmm_init() void {}
