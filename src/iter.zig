pub const Iterator = struct {
    range: Range,

    const Self = @This();

    pub fn next(self: *Self) ?usize {
        if (self.range.inclusive and self.range.start > self.range.end) {
            return null;
        }

        if (!self.range.inclusive and self.range.start >= self.range.end) {
            return null;
        }
        const old = self.range.start;

        self.range.start += 1;

        return old;
    }
};

pub const Range = struct {
    start: u64,
    end: u64,
    inclusive: bool,
    const Self = @This();

    /// Range like [start; start+end]
    pub fn new_inclusive(base: usize, size: usize) Self {
        return .{
            .start = base,
            .end = size,
            .inclusive = true,
        };
    }

    /// Range like [start; start+end[
    pub fn new_exclusive(base: usize, size: usize) Self {
        return .{
            .start = base,
            .end = size,
            .inclusive = false,
        };
    }

    pub fn iter(self: Self) Iterator {
        return Iterator{
            .range = self,
        };
    }

    pub fn len(self: *@This()) u64 {
        return self.end - self.start;
    }
};
