const serial = @import("../drivers/serial.zig");

pub const Heap = @This();

hbase: ?[*]u8 = null,
hsize: ?usize = null,

const AllocHeader = packed struct {
    size: usize,
    // Put void here cause zig compiler crash when try align(1) ptr of AllocHeader
    prev_block: ?*void,
    next_block: ?*void,
    is_free: bool,

    fn setHeader(base: *void, size: usize) *align(1) AllocHeader {
        const header: *align(1) AllocHeader = @ptrCast(base);
        header.* = AllocHeader{
            .size = size,
            .prev_block = null,
            .next_block = null,
            .is_free = true,
        };

        return header;
    }

    fn getHeader(base: *void) *align(1) AllocHeader {
        return @ptrCast(base);
    }

    fn getHeaderFromData(base: *void) *align(1) AllocHeader {
        return @ptrFromInt(@intFromPtr(base) - @sizeOf(AllocHeader));
    }

    fn getData(self: *align(1) const AllocHeader) [*]u8 {
        const dataptr: [*]u8 = @ptrFromInt(@intFromPtr(self) + @sizeOf(AllocHeader));

        return dataptr;
    }

    fn getNext(self: *align(1) const AllocHeader) ?*align(1) AllocHeader {
        if (self.next_block == null) {
            return null;
        }

        return @ptrCast(self.next_block.?);
    }

    fn getPrev(self: *align(1) const AllocHeader) ?*align(1) AllocHeader {
        if (self.prev_block == null) {
            return null;
        }

        return @ptrCast(self.prev_block.?);
    }

    fn mergePrevious(self: *align(1) const AllocHeader) !void {
        if (self.getPrev()) |prev| {
            prev.size += self.size + @sizeOf(AllocHeader);
            prev.next_block = self.next_block;

            return;
        }

        return error.NoPrevious;
    }

    fn mergeNext(self: *align(1) AllocHeader) !void {
        if (self.getNext()) |next| {
            self.size += next.size + @sizeOf(AllocHeader);
            self.next_block = next.next_block;
            return;
        }

        return error.NoNext;
    }

    fn mergeNextWithPrevious(self: *align(1) const AllocHeader) !void {
        if (self.getNext()) |next| {
            if (self.getPrev()) |prev| {
                prev.size += next.size + @sizeOf(AllocHeader);
                prev.next_block = next.next_block;
                return;
            }

            return error.NoPrevious;
        }

        return error.NoNext;
    }

    pub fn debug(self: *align(1) AllocHeader) void {
        const Debug = struct {
            pub fn drawArrow() void {
                serial.println("{s: >12}|", .{""});
                serial.println("{s: >11}/", .{""});
                serial.println("{s: >10}v", .{""});
            }

            pub fn drawBox(is_free: bool, size: usize) void {
                serial.println("{0s: >6}+{0s:->14}+", .{""});
                if (is_free) {
                    serial.println("{s: >6}|{s: ^14}|", .{ "", "free" });
                } else {
                    serial.println("{s: >6}|{s: ^14}|", .{ "", "used" });
                }

                serial.println("{s: >6}|{: ^14}|", .{ "", size });

                serial.println("{0s: >6}+{0s:->14}+", .{""});
            }
        };
        serial.println("0x{x} 0x{x}", .{ @intFromPtr(self), @intFromPtr(self) + self.size });
        Debug.drawBox(self.is_free, self.size);

        if (self.next_block == null) {
            Debug.drawArrow();
            serial.println("{s: ^20}", .{"null"});
        } else {
            Debug.drawArrow();
            AllocHeader.getHeader(self.next_block.?).debug();
        }
    }
};

pub fn init(base: [*]u8, size: usize) Heap {
    _ = AllocHeader.setHeader(@ptrCast(base), size);

    return .{
        .hbase = base,
        .hsize = size,
    };
}

pub fn alloc(self: *align(1) Heap, size: usize) ![]u8 {
    if (self.hbase == null) {
        return error.HeapNotInitialize;
    }

    var header = AllocHeader.getHeader(@ptrCast(self.hbase));

    while (header.next_block != null) {
        header = @ptrCast(header.next_block.?);
    }

    if (size + @sizeOf(AllocHeader) > header.size and header.next_block == null) {
        return error.NotEnougthMem;
    }

    const data: [*]u8 = header.getData();

    const next_header = AllocHeader.setHeader(@ptrCast(&data[size]), header.size - size - @sizeOf(AllocHeader));
    next_header.prev_block = @ptrCast(header);

    header.next_block = @ptrCast(next_header);
    header.size = size;
    header.is_free = false;

    return data[0..size];
}

pub fn create(self: *align(1) Heap, comptime T: type) !*T {
    return @ptrCast(@alignCast(try self.alloc(@sizeOf(T))));
}

pub fn free(base: anytype) !void {
    // From allocator code: https://ziglang.org/documentation/master/std/#std.mem.Allocator.destroy
    const info = @typeInfo(@TypeOf(base)).pointer;
    const T = info.child;
    if (@sizeOf(T) == 0) return;
    const non_const_ptr = @as([*]u8, @ptrCast(@constCast(base)));

    const header = AllocHeader.getHeaderFromData(@ptrCast(non_const_ptr));

    if (header.getPrev()) |prev| {
        if (prev.is_free) {
            try header.mergePrevious();

            if (header.getNext()) |next| {
                if (next.is_free) {
                    try header.mergeNextWithPrevious();
                }
            }
        }

        return;
    }

    if (header.getNext()) |next| {
        if (next.is_free) {
            try header.mergeNext();
        }
    }

    header.is_free = true;
}

fn test_heap() Heap {
    var gpa = @import("std").heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const mem = allocator.alloc(u8, 4096) catch {
        @panic("Cannot run test");
    };
    return init(@ptrCast(mem), 4096);
}

test "alloc" {
    var heap = test_heap();
    const allocated = try heap.alloc(200);
    try @import("std").testing.expectEqual(200, allocated.len);
}

test "alloc_and_free" {
    var heap = test_heap();
    const allocated = try heap.alloc(200);

    try @import("std").testing.expectEqual(200, allocated.len);

    try free(allocated);

    try @import("std").testing.expectEqual(4096, AllocHeader.getHeader(@ptrCast(heap.hbase.?)).size);
}

test "alloc_twice" {
    var heap = test_heap();
    const allocated = try heap.alloc(200);
    const allocated_twice = try heap.alloc(200);

    try @import("std").testing.expectEqual(200, allocated_twice.len);
    try @import("std").testing.expectEqual(@intFromPtr(allocated.ptr) + @sizeOf(AllocHeader) + allocated.len, @intFromPtr(allocated_twice.ptr));

    try free(allocated);
    try free(allocated_twice);

    try @import("std").testing.expectEqual(4096, AllocHeader.getHeader(@ptrCast(heap.hbase.?)).size);
}

test "alloc_too_much" {
    var heap = test_heap();

    try @import("std").testing.expectError(error.NotEnougthMem, heap.alloc(4096));
}

test "alloc_max" {
    var heap = test_heap();

    const allocated = try heap.alloc(4096 - @sizeOf(AllocHeader));
    try @import("std").testing.expectEqual(4096 - @sizeOf(AllocHeader), allocated.len);
}
