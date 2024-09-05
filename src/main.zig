const serial = @import("./drivers/serial.zig");
const gdt = @import("./gdt.zig");
const idt = @import("./idt.zig");
const builtin = @import("std").builtin;
const limine = @import("limine");
const pmm = @import("./mem/pmm.zig");
const build_options = @import("build_options");
const vmm = @import("./mem/vmm.zig");
const fb = @import("./drivers/fbscreen.zig");
const limine_rq = @import("limine_rq.zig");
const acpi = @import("./acpi/acpi.zig");
const ps2 = @import("./drivers/ps2.zig");
const psf = @import("./psf.zig");
const pci = @import("./drivers/pci.zig");
const smp = @import("./smp.zig");
const syscall = @import("syscall.zig");
const heap = @import("./mem/heap.zig");
const idiot = @embedFile("./idiot");

var kheap: ?heap.Heap = null;

pub inline fn get_rbp() usize {
    return asm volatile (
        \\ mov %%rsp, %[value]
        : [value] "=r" (-> usize),
    );
}

var max: u8 = 0;

const Stacktrace = packed struct {
    next: *Stacktrace,
    addr: u64,
};

// Only works in debug mode (TODO: Make this working in release mode)
pub fn stacktrace() void {
    if (max > 3) {
        while (true)
            asm volatile ("hlt");
    }

    max += 1;

    serial.println("Stacktrace:", .{});

    var rbp: *align(1) Stacktrace = @ptrFromInt(get_rbp());

    var i: u32 = 0;
    while (@intFromPtr(rbp) != 0x0) : (i += 1) {
        serial.println("{}: 0x{X}", .{ i, rbp.addr });
        rbp = rbp.next;
    }
}

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    serial.println(
        \\====== This is a panic message ======
        \\{s}
    , .{msg});
    stacktrace();

    var screen = &fb.screen.?;

    screen.resetAll();
    screen.println("===== PANIC =====");
    screen.println(msg);

    while (true) {}
}

pub fn main() !noreturn {
    _ = serial.Serial.init() catch {
        asm volatile ("hlt");
        return error.CannotWrite;
    };

    const cpu = @import("./cpu.zig");
    serial.println("id: {}", .{cpu.get_id()});

    gdt.init();
    idt.init();

    if (limine_rq.memory_map.response) |response| {
        try pmm.pmm_init(response, limine_rq.hhdm.response.?);
    }

    serial.println("HHDM: 0x{x} KADDR: 0x{x}", .{ limine_rq.hhdm.response.?.offset, limine_rq.kaddr_req.response.?.virtual_base });
    try vmm.init(limine_rq.memory_map.response.?);

    const heap_base = try pmm.alloc(4096);
    kheap = heap.init(@ptrCast(heap_base), 4096);

    if (limine_rq.framebuffer.response) |response| {
        if (response.framebuffer_count > 0) {
            const framebuf = response.framebuffers_ptr[0];
            serial.println("{any}", .{framebuf});

            const a: *align(1) const psf.Psf2 = @ptrCast(psf.lucida);
            fb.fb_ptr = fb.Framebuffer.init(@intFromPtr(framebuf.address), framebuf.height, framebuf.width, framebuf.pitch, framebuf.bpp, a);
        }
    }

    try acpi.init();

    try ps2.init();

    fb.screen.?.println("ZROS - 0.0.1+" ++ build_options.git_version);
    fb.screen.?.println("Hewwo worwd");
    fb.screen.?.print(0xA0);
    const str = try kheap.?.alloc(256);

    const printed = try @import("std").fmt.bufPrint(str, "HHDM: 0x{x} KADDR: 0x{x}", .{ limine_rq.hhdm.response.?.offset, limine_rq.kaddr_req.response.?.virtual_base });
    fb.screen.?.println(printed);

    const mcfg: *align(1) acpi.Mcfg = @ptrCast(try acpi.xspt.?.get(&"MCFG"));

    serial.println("{} {any}", .{ mcfg.nb_of_entry(), mcfg.get_configuration() });

    try smp.init();
    syscall.init();

    var a: u64 = 0;

    serial.println("Phys: {x}, Virt: {x}, Addr of a: {x}, Addr of a: {x}", .{ limine_rq.kaddr_req.response.?.physical_base, limine_rq.kaddr_req.response.?.virtual_base, @intFromPtr(&a) - limine_rq.kaddr_req.response.?.virtual_base, @import("mem/mem.zig").mmap_virt_to_phys(@intFromPtr(&a)) });

    const stack = try pmm.alloc(4096);

    serial.println("0x{X}", .{@intFromPtr(stack)});

    @import("./drivers/hpet.zig").hpet.?.sleep(1000);

    try vmm.alloc(vmm.kernel_pml4.?, 0x1000, @intFromPtr(stack), vmm.PmlEntryFlag.USER | vmm.PmlEntryFlag.READ_WRITE | vmm.PmlEntryFlag.PRESENT);
    syscall.load_ring_3_z(0x1000, @intFromPtr(&idiot));

    while (true) {
        asm volatile ("hlt");
    }
}

export fn _start() noreturn {
    asm volatile (
        \\xor %%rbp, %%rbp
        \\push %%rbp
    );

    main() catch |i| {
        serial.println("{}", .{i});
    };
    while (true) {
        asm volatile ("hlt");
    }
}
