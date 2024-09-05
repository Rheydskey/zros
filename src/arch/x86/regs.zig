pub const Cr3 = packed struct(u64) {
    _reserved: u12 = 0,
    page_base_addr: u52 = 0,

    pub fn write_page_base(self: *Cr3, pagemap_base: u64) void {
        self.page_base_addr = @truncate(pagemap_base);
    }

    pub fn apply(self: *Cr3) void {
        const cr3_value: u64 = @bitCast(self.*);
        asm volatile ("mov %%cr3, %[value]"
            :
            : [value] "r" (cr3_value),
            : "memory"
        );
    }
};
