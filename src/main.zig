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
const psf = @import("./psf.zig");
const smp = @import("./smp.zig");
const syscall = @import("syscall.zig");
const heap = @import("./mem/heap.zig");
const idiot = @embedFile("./idiot");
const context = @import("./sched/ctx.zig");
const drivers = @import("./drivers/drivers.zig");

var kheap: ?heap.Heap = null;

pub inline fn get_rbp() usize {
    return asm volatile (
        \\ mov %%rbp, %[value]
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

    serial.println_nolock("Stacktrace:", .{});

    var rbp: *align(1) Stacktrace = @ptrFromInt(get_rbp());

    var i: u32 = 0;
    while (@intFromPtr(rbp) != 0x0) : (i += 1) {
        serial.println_nolock("{}: 0x{X}", .{ i, rbp.addr });
        rbp = rbp.next;
    }
}

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    serial.println_nolock(
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

    const heap_base = try pmm.alloc(0x10000);
    kheap = heap.init(@ptrCast(heap_base), 0x10000);

    if (limine_rq.framebuffer.response) |response| {
        if (response.framebuffer_count > 0) {
            const framebuf = response.framebuffers_ptr[0];
            serial.println("{any}", .{framebuf});

            const a: *align(1) const psf.Psf2 = @ptrCast(psf.lucida);
            fb.fb_ptr = fb.Framebuffer.init(@intFromPtr(framebuf.address), framebuf.height, framebuf.width, framebuf.pitch, framebuf.bpp, a);
        }
    }

    const kernel_stack = try kheap.?.alloc(16000);

    gdt.tss_init(@intFromPtr(kernel_stack.ptr) + 16000);

    try drivers.init();

    fb.screen.?.println("ZROS - 0.0.1+" ++ build_options.git_version);
    fb.screen.?.println("Hewwo worwd");
    fb.screen.?.print(0xA0);

    const str = try kheap.?.alloc(256);

    const printed = try @import("std").fmt.bufPrint(str, "HHDM: 0x{x} KADDR: 0x{x}", .{ limine_rq.hhdm.response.?.offset, limine_rq.kaddr_req.response.?.virtual_base });
    fb.screen.?.println(printed);

    try smp.init();
    syscall.init();

    const code: [*]u8 = @ptrCast(try pmm.alloc(4096));

    @import("std").mem.copyForwards(u8, code[0..4096], idiot[0..idiot.len]);

    const stack = try pmm.alloc(4096);

    try vmm.remap_page(vmm.kernel_pml4.?, 0x50000000, @intFromPtr(stack), vmm.PmlEntryFlag.USER | vmm.PmlEntryFlag.READ_WRITE | vmm.PmlEntryFlag.PRESENT);

    try vmm.remap_page(vmm.kernel_pml4.?, 0x50005000, @intFromPtr(code), vmm.PmlEntryFlag.USER | vmm.PmlEntryFlag.READ_WRITE | vmm.PmlEntryFlag.PRESENT);

    const ctx: context.Context = .{ .stack = 0x50000000 + 4096, .kernel_stack = @intFromPtr(kernel_stack.ptr) + 16000 };

    syscall.set_gs(@intFromPtr(&ctx));

    syscall.load_ring_3_z(0x50000000 + 4096, 0x50005000);

    while (true) {
        asm volatile ("hlt");
    }
}

export fn _start() noreturn {
    main() catch |i| {
        serial.println("{}", .{i});
    };

    while (true) {
        asm volatile ("hlt");
    }
}
