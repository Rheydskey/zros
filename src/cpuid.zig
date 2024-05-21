pub const Cpuid = struct {
    eax: u32 = 0,
    ebx: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,

    const VendorId = union {
        string: [12]u8,
        regs: [3]u32,
    };

    pub fn read_vendor() VendorId {
        var self: Cpuid = .{};

        self.read_cpuid(0);

        return .{ .regs = .{ self.ebx, self.edx, self.ecx } };
    }

    pub fn read_cpuid(self: *Cpuid, cpuid_value: u32) void {
        var eax_value: u32 = 0;
        var ebx_value: u32 = 0;
        var ecx_value: u32 = 0;
        var edx_value: u32 = 0;

        asm (
            \\ cpuid
            : [_] "={eax}" (eax_value),
              [_] "={ebx}" (ebx_value),
              [_] "={ecx}" (ecx_value),
              [_] "={edx}" (edx_value),
            : [cpuid_offset] "{eax}" (cpuid_value),
        );

        self.eax = eax_value;
        self.ebx = ebx_value;
        self.ecx = ecx_value;
        self.edx = edx_value;
    }
};
