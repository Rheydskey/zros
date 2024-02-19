const serial = @import("./serial.zig");
const Range = @import("./iter.zig").Range;

pub const State = enum(u8) {
    Unused = 0,
    Used = 1,

    pub fn flip(self: *@This()) @This() {
        if (self.* == State.Unused) {
            return State.Used;
        }

        return State.Unused;
    }
};

pub const BitMapU8 = struct {
    entries: [*]u8,
    size: usize,
    next_free_block: usize = 0,

    const bit_size: usize = @bitSizeOf(u8);
    const Self = @This();

    pub fn new(base: *void, s: usize) @This() {
        serial.println("Create a bitmap of {}kb", .{s / 1024});
        serial.println("Bitsize of {s} is {}", .{ @typeName(u8), @bitSizeOf(u8) });

        return .{ .entries = @ptrCast(base), .size = s };
    }

    pub fn init(s: *@This()) void {
        serial.println("Initializing bitmap", .{});
        for (0..s.size) |i| {
            s.set(i);
        }
    }

    pub fn set(self: *Self, nth: usize) void {
        if (nth > self.size) {
            return;
        }

        self.entries[nth / bit_size] |= @as(u8, 1) << @truncate(nth % bit_size);
    }

    pub fn unset(self: *Self, nth: usize) void {
        if (nth > self.size) {
            return;
        }

        // serial.println("[{}] 0b{b} & 0b{b} => 0b{b}", .{ nth, self.entries[nth / bit_size], ~(@as(u8, 1) << @truncate(nth % bit_size)), self.entries[nth / bit_size] & ~(@as(u8, 1) << @truncate(nth % bit_size)) });

        self.entries[nth / bit_size] &= ~(@as(u8, 1) << @truncate(nth % bit_size));
    }

    pub fn get(self: *@This(), nth: usize) State {
        return @enumFromInt((self.entries[nth / bit_size] >> @truncate(nth % bit_size)) & 1);
    }

    pub fn unset_range(self: *Self, range: Range) !void {
        var iterator = range.iter();
        while (iterator.next()) |i| {
            serial.println("will set {}", .{i});
            if (i > self.size * 8) {
                return error.NotEnoughtMemory;
            }

            self.unset(i);
        }
    }

    pub fn set_range(self: *Self, range: Range) !void {
        var iterator = range.iter();
        while (iterator.next()) |i| {
            if (i > self.size) {
                return error.NotEnoughtMemory;
            }

            self.set(i);
        }
    }

    pub fn alloc(self: *Self, range: Range) !void {
        while (range.iter()) |i| {
            if (i > self.entries.len) {
                return error.NotEnoughtMemory;
            }

            self.set(i);
        }
    }

    pub fn debug(self: *Self) void {
        serial.println("base: {x} size: {}", .{ &self.entries[0], self.size });

        var start: u64 = 0;
        var state = self.get(start);
        for (0..self.size) |i| {
            if (state != self.get(i)) {
                serial.println("0x{x} - 0x{x} : {s}", .{ start, start + i, @tagName(state) });
                state = state.flip();
                start = start + i + 1;
            }
        }

        serial.println("0x{x} - 0x{x} : {s}", .{ start, self.size - start, @tagName(state) });
    }
};

pub fn BitMapU8_with_size(size: usize) type {
    return struct {
        entries: *u8,
        size: usize = size,
        next_free_block: usize = 0,

        const bit_size: usize = @bitSizeOf(u8);
        const Self = @This();

        pub fn new(s: usize) @This() {
            return .{ .entries = undefined, .size = s };
        }

        pub fn init(s: *@This()) void {
            serial.println("Initializing bitmap", .{});
            for (0..s.size) |i| {
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
}

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
