const std = @import("std");
const utils = @import("zros").utils;

test "is_align" {
    try std.testing.expectEqual(true, utils.is_align(0x0, 8));
}
