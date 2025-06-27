pub const RegsContext = @import("../arch/x86/idt/interrupt.zig").Context;

pub const Status = enum { READY, RUNNING, DEAD, IN_SYSCALL };

pub const Context = packed struct {
    stack: u64,
    kernel_stack: u64,

    regs: RegsContext,

    pub fn init(self: *@This(), ip: u64, stackptr: u64, kernel_stackptr: u64, is_user: bool) void {
        self.regs.iret.rip = ip;
        self.regs.iret.flags = 202;

        if (is_user) {
            self.regs.iret.cs = 0x1B;
            self.regs.iret.ss = 0x23;
        } else {
            self.regs.iret.cs = 0x08;
            self.regs.iret.ss = 0x10;
        }

        self.regs.regs.rbp = 0;

        self.regs.iret.rsp = stackptr;

        self.stack = stackptr;
        self.kernel_stack = kernel_stackptr;
        @import("../drivers/serial.zig").println("New task: {any}", .{self});
    }

    pub fn store_regs(self: *@This(), regs: *const RegsContext) void {
        self.regs = regs.*;
    }

    pub fn load_to(self: *const @This(), regs: *RegsContext) void {
        @import("root").syscall.setGs(@intFromPtr(self));

        regs.* = self.regs;
    }
};
