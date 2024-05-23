pub const Cpuid = struct {
    eax: u32 = 0,
    ebx: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,

    pub fn fromRegister(self: *const Cpuid, comptime t: type) t {
        return @bitCast([_]u32{ self.eax, self.ebx, self.edx, self.ecx });
    }

    const Vendor = packed struct(u128) {
        hightest_call: u32,
        vendor_string: u96,

        pub fn getVendorString(self: *const Vendor) []const u8 {
            return @import("std").mem.asBytes(&self.vendor_string);
        }
    };

    pub fn read_vendor() Vendor {
        var self: Cpuid = .{};

        self.read_cpuid(0);

        return self.fromRegister(Vendor);
    }

    const CpuInfo = packed struct(u128) {
        processor_version: packed struct(u32) {
            stepping_id: u4,
            model: u4,
            family_id: u4,
            processor_type: u2,
            reserved: u2,
            extended_model: u4,
            extended_family: u8,
            _reserved: u4,
        },
        ebx: packed struct(u32) {
            brand_index: u8,
            clflush: u8,
            max_id: u8,
            local_apic_id: u8,
        },
        other: u64,
    };

    pub fn read_cpu_info() CpuInfo {
        var self: Cpuid = .{};

        self.read_cpuid(1);

        return self.fromRegister(CpuInfo);
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
