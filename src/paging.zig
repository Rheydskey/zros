pub const PmlFlags = enum(usize) {
    USER = 1 << 0,
    WRITABLE = 1 << 1,
    WRITE_THROUGHT = 1 << 2,
};

pub const PmlEntry = packed struct(u64) {
    present: bool = true,
    read_write: bool,
    user: bool,
    page_write_throught: bool,
    caching_disable: bool = false,
    accessed: bool = false,
    available: bool = false,
    huge_page: bool = false,
    _available: u4 = 0,
    address: u52,

    pub inline fn new(physical: usize, flags: usize) PmlEntry {
        return .{
            .read_write = flags & PmlFlags.WRITABLE,
            .user = flags & PmlFlags.USER,
            .page_write_throught = flags & PmlFlags.WRITE_THROUGHT,
            .address = physical >> 12,
        };
    }
};

pub const PageMapLevelX = struct {
    pub fn level(l: u8) type {
        return struct {
            entries: [512]PmlEntry,

            pub inline fn get_index(address: usize) usize {
                return ((address & (0x1ff << (12 + l * 9))) >> (12 + l * 9));
            }
        };
    }
};

const PageTable = PageMapLevelX.level(1);
const PageDirectory = PageMapLevelX.level(2);
const PageDirectoryPointer = PageMapLevelX.level(3);
const PmlEntry4 = PageMapLevelX.level(4);
