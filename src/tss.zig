pub const TaskSegment = packed struct {
    reserved1: u32 = 0,
    rsp: packed struct(u192) {
        rsp0: u64,
        rsp1: u64,
        rsp2: u64,
    },
    reserved2: u64 = 0,
    reserved3: u64 = 0,
    ist: packed struct {
        ist1: u64,
        ist2: u64,
        ist3: u64,
        ist4: u64,
        ist5: u64,
        ist6: u64,
        ist7: u64,
    },
    reserved4: u64 = 0,
    iopb: packed struct(u32) {
        reserved: u16 = 0,
        iopb: u16,
    },
};
