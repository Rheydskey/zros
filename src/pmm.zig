const serial = @import("./serial.zig");
const Range = @import("./iter.zig").Range;

pub fn BitMap(comptime num_entries: usize, comptime entry_type: type) type {
    return struct {
        entries: [num_entries]entry_type,
        next_free_block: usize,

        const Self = @This();

        pub fn init(self: *Self) void {
            serial.print("Initializing bitmap", .{});
            for (0..self.entries.len) |i| {
                self.entries[i] = 0;
            }
        }

        // Bool act like a result
        pub fn alloc(self: *Self, range: Range) bool {
            _ = range;
            _ = self;
        }
    };
}
