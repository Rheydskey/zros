pub const context = @import("ctx.zig");
pub const serial = @import("../drivers/serial.zig");
pub const Heap = @import("../mem/heap.zig").Heap;

pub var is_running = false;
pub var base: ?*Task = undefined;
pub var current_process: ?*Task = null;

pub const Task = struct {
    id: ?u16 = null,
    ctx: context.Context,
    status: context.Status = .READY,
    next_task: ?*Task = null,

    pub fn create(alloc: *align(1) Heap) !*@This() {
        return try alloc.create(@This());
    }

    pub fn destroy(self: *@This(), alloc: *align(1) Heap) !void {
        alloc.free(self);
    }

    pub fn init(self: *@This(), ip: u64, stackptr: u64, kernel_stackptr: u64, is_user: bool) void {
        self.ctx.init(ip, stackptr, kernel_stackptr, is_user);
    }
};

pub fn add_process(new_task: *Task) !void {
    if (base == null) {
        base = new_task;
        new_task.id = 0;
        current_process = base;
        return;
    }

    var id: u16 = 1;
    var task = base;

    while (task.?.next_task != null) {
        task = task.?.next_task;
        id += 1;
    }

    new_task.id = id;
    task.?.next_task = new_task;
}

pub fn current() ?*Task {
    return current_process;
}

pub fn next() ?*Task {
    if (current_process == null) {
        return null;
    }

    if (current_process.?.next_task) |next_task| {
        current_process = next_task;
        return current_process;
    }

    current_process = base;

    return current_process;
}

pub fn schedule(ctx: *context.RegsContext) !void {
    if (!is_running) return;

    var current_task = current() orelse return;

    if (current_task.status == .RUNNING) {
        current_task.ctx.store_regs(ctx);
        current_task.status = .READY;
    }

    var next_task = next() orelse return error.NoProcess;

    serial.println_nolock("new task {?}", .{next_task.id});
    next_task.status = .RUNNING;

    current().?.ctx.load_to(ctx);
}
