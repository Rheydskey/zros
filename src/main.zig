pub const drivers = @import("./drivers/drivers.zig");
const pci = @import("./drivers/pci.zig");
const serial = drivers.serial;
pub const cpu = @import("arch/x86/cpu.zig");
const gdt = @import("./arch/x86/gdt.zig");
const idt = @import("./arch/x86/idt.zig");
pub const syscall = @import("arch/x86/syscall.zig");
const std = @import("std");
const builtin = std.builtin;
const build_options = @import("build_options");
const pmm = @import("./mem/pmm.zig");
const heap = @import("./mem/heap.zig");
const vmm = @import("./mem/vmm.zig");
const fb = drivers.fb;
pub const scheduler = @import("./sched/scheduler.zig");
const limine_rq = @import("limine_rq.zig");
const psf = @import("./psf.zig");
const smp = @import("./smp.zig");
pub const assembly = @import("asm.zig");
pub const utils = @import("utils.zig");

const idiot = @embedFile("./idiot");
const idiot2 = @embedFile("./idiot2");

var kheap: ?heap.Heap = null;

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, ret_addr: ?usize) noreturn {
    serial.println_nolock(
        \\====== This is a panic message ======
        \\{s}
    , .{msg});

    if (fb.screen != null) {
        var screen = &fb.screen.?;

        screen.resetAll();
        screen.println("===== PANIC =====");
        screen.println(msg);
    }

    const addr = ret_addr orelse @returnAddress();

    var si = std.debug.StackIterator.init(addr, null);
    defer si.deinit();

    if (fb.screen != null) {
        var screen = &fb.screen.?;

        screen.println("Stacktrace:");
    }

    serial.println_nolock("Stacktrace:", .{});

    while (si.next()) |trace| {
        if (fb.screen) |_| {
            var screen = &fb.screen.?;
            _ = screen.writer().print("0x{X}\n", .{trace}) catch {};
        }

        serial.println_nolock("0x{X}", .{trace});
    }

    serial.println_nolock("End of stacktrace", .{});

    while (true) {
        assembly.hlt();
    }
}

fn load_tasks(kernel_stack: []u8) !void {
    const code: [*]u8 = @ptrCast(try pmm.alloc(4096));

    @import("std").mem.copyForwards(u8, code[0..4096], idiot[0..idiot.len]);

    const stack = try pmm.alloc(4096);

    try vmm.remap_page(vmm.kernel_pml4.?, 0x50000000, @intFromPtr(stack), vmm.PmlEntryFlag.USER | vmm.PmlEntryFlag.READ_WRITE | vmm.PmlEntryFlag.PRESENT);

    try vmm.remap_page(vmm.kernel_pml4.?, 0x50005000, @intFromPtr(code), vmm.PmlEntryFlag.USER | vmm.PmlEntryFlag.READ_WRITE | vmm.PmlEntryFlag.PRESENT);

    var task = try scheduler.Task.create(&kheap.?);

    task.init(0x50005000, 0x50000000 + 4096, @intFromPtr(kernel_stack.ptr) + 16000, true);

    try scheduler.add_process(task);

    const code2: [*]u8 = @ptrCast(try pmm.alloc(4096));

    @import("std").mem.copyForwards(u8, code2[0..4096], idiot2[0..idiot2.len]);

    const stack2 = try pmm.alloc(4096);

    try vmm.remap_page(vmm.kernel_pml4.?, 0x40000000, @intFromPtr(stack2), vmm.PmlEntryFlag.USER | vmm.PmlEntryFlag.READ_WRITE | vmm.PmlEntryFlag.PRESENT);

    try vmm.remap_page(vmm.kernel_pml4.?, 0x40005000, @intFromPtr(code2), vmm.PmlEntryFlag.USER | vmm.PmlEntryFlag.READ_WRITE | vmm.PmlEntryFlag.PRESENT);

    var task2 = try scheduler.Task.create(&kheap.?);

    task2.init(0x40005000, 0x40000000 + 4096, @intFromPtr(kernel_stack.ptr) + 16000, true);

    try scheduler.add_process(task2);

    scheduler.is_running = true;
}

pub fn main() !noreturn {
    _ = serial.Serial.init() catch {
        asm volatile ("hlt");
        return error.CannotWrite;
    };

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

    fb.screen.?.println("ZROS - 0.0.1+" ++ build_options.git_version);
    fb.screen.?.println("Hewwo worwd");
    fb.screen.?.print(0xA0);

    try drivers.init();

    const str = try kheap.?.alloc(256);

    const printed = try @import("std").fmt.bufPrint(str, "HHDM: 0x{x} KADDR: 0x{x}", .{ limine_rq.hhdm.response.?.offset, limine_rq.kaddr_req.response.?.virtual_base });
    fb.screen.?.println(printed);

    // try smp.init();
    syscall.init();

    // const acpi = @import("./acpi/acpi.zig");

    // pci.scan(acpi.mcfg.?.get_configuration());

    try load_tasks(kernel_stack);

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
