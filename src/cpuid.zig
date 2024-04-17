pub fn get_cpuid() u64 {
    const rax: u64 = 0;
    const rbx: u64 = 0;
    const rcx: u64 = 0;
    const rdx: u64 = 0;

    asm volatile (
        \\ xorq %rax, %rax
        \\ cpuid
        :
        : [rax] "{rax}" (rax),
          [rbx] "{rbx}" (rbx),
          [rcx] "{rcx}" (rcx),
          [rdx] "{rdx}" (rdx),
        : "rax", "rbx", "rcx", "rdx"
    );

    return rdx;
}
