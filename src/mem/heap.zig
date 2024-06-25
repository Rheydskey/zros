const serial = @import("../drivers/serial.zig");

pub const Heap = @This();

hbase: ?[*]u8 = null,
hsize: ?usize = null,

const AllocHeader = packed struct {
    size: usize,
    // Put void here cause zig crash when try align(1) ptr of AllocHeader
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

    fn getHeaderFromDataBase(base: *void) *align(1) AllocHeader {
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

pub fn free(base: anytype) !void {
    // From allocator code: https://ziglang.org/documentation/master/std/#std.mem.Allocator.destroy
    const info = @typeInfo(@TypeOf(base)).Pointer;
    const T = info.child;
    if (@sizeOf(T) == 0) return;
    const non_const_ptr = @as([*]u8, @ptrCast(@constCast(base)));

    const header = AllocHeader.getHeaderFromDataBase(@ptrCast(non_const_ptr));

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
    const mem = try allocator.alloc(u8, 4096);
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
