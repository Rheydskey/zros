const serial = @import("./serial.zig");
const Range = @import("./iter.zig").Range;

pub const BitMapU8 =
    struct {
    entries: [10]u8,
    next_free_block: usize = 0,

    const bit_size: usize = @bitSizeOf(u8);
    const Self = @This();

    pub fn new() @This() {
        return .{ .entries = undefined };
    }

    pub fn init(s: *@This()) void {
        serial.println("Initializing bitmap", .{});
        for (0..s.entries.len) |i| {
            s.entries[i] = 0;
        }
    }

    pub fn set(self: *Self, nth: usize) void {
        if (nth > self.entries.len) {
            return;
        }

        self.entries[nth / bit_size] |= @as(u8, 1) << @truncate(nth % bit_size);
    }

    pub fn unset(self: *Self, nth: usize) void {
        if (nth > self.entries.len) {
            return;
        }

        // !(!0b11101 | 1 << 0) & 0b11101 = 0b11100
        self.entries[nth / bit_size] &= ~(~self.entries[nth / bit_size] | @as(u8, 1) << @truncate(nth % bit_size));
    }

    pub fn get(self: *@This(), nth: usize) bool {
        return ((self.entries[nth / bit_size] >> @truncate(nth % bit_size)) & 1) == 1;
    }

    /// Bool act like a result
    pub fn alloc(self: *Self, range: Range) bool {
        while (range.iter()) |i| {
            if (i > self.entries.len) {
                return false;
            }

            self.set(i);
        }

        true;
    }

    pub fn debug(self: Self) void {
        for (self.entries) |i| {
            serial.println("0b{b:0>8}", .{i});
        }
    }
};

pub fn BitMap(comptime num_entries: usize, comptime entry_type: type) type {
    return struct {
        entries: [num_entries]entry_type,
        next_free_block: usize = 0,

        const bit_size = @bitSizeOf(entry_type);
        const Self = @This();

        pub fn new() @This() {
            return .{ .entries = undefined };
        }

        pub fn init(s: *@This()) void {
            serial.print("Initializing bitmap", .{});
            for (0..s.entries.len) |i| {
                s.entries[i] = 0;
            }
        }

        pub fn typeName(self: Self) void {
            serial.println("A: {s}", .{@typeName(self)});
        }

        pub fn set(self: *Self, nth: usize) void {
            if (nth > self.entries.len) {
                return;
            }

            self.entries[nth / bit_size] |= 1 << nth % bit_size;
        }

        pub fn unset(self: *Self, nth: usize) void {
            if (nth > self.entries.len) {
                return;
            }

            // !(!0b11101 | 1 << 0) & 0b11101 = 0b11100
            self.entries[nth / @bitSizeOf(entry_type)] &= !(!self.entries[nth / @bitSizeOf(entry_type)] | 1 << nth % @bitSizeOf(entry_type));
        }

        /// Bool act like a result
        pub fn alloc(self: *Self, range: Range) bool {
            while (range.iter()) |i| {
                if (i > self.entries.len) {
                    return false;
                }

                self.set(i);
            }

            true;
        }

        pub fn debug(self: Self) void {
            for (self.entries) |i| {
                serial.println("{b}", .{i});
            }
        }
    };
}
