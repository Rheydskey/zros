const pci = @import("./pci.zig");
const rq = @import("../limine_rq.zig");
const serial = @import("./serial.zig");
const pmm = @import("../mem/pmm.zig");
const hpet = @import("../drivers/hpet.zig");

// https://github.com/vlang/vinix/blob/main/kernel/modules/dev/hda/hda.v
// https://osdev.wiki/wiki/Intel_High_Definition_Audio#Device_Registers
// https://www.intel.com/content/dam/www/public/us/en/documents/product-specifications/high-definition-audio-specification.pdf
const HdaRegister = packed struct {
    global_caps: GlobalCapabilities,
    min_ver: u8,
    maj_ver: u8,
    output_payload_caps: u16,
    input_payload_caps: u16,
    global_ctrl: packed struct(u32) {
        controller_reset: u1,
        flush_control: u1,
        reserved0: u6,
        accept_unsollicited_response: bool,
        reserved1: u23,

        pub fn reset(self: *volatile @This()) void {
            // Controller is running, we'll stop it
            if ((self.controller_reset & 1) != 0) {
                @panic("HDA: The controller is running");
            }

            self.controller_reset = 0;

            while (self.controller_reset != 0) {}

            serial.println("Stage 1", .{});

            hpet.hpet.?.sleep(200);

            self.controller_reset = 1;
            while (true) {
                if (self.controller_reset != 0) {
                    break;
                }
            }

            serial.println("R U ON ????", .{});
        }
    },
    wake_enable: u16,
    wake_status: u16,
    global_status: u16,
    reserved0: u48,
    output_stream_payload_caps: u16,
    input_stream_payload_caps: u16,
    reserved1: u32,
    interrupt_ctrl: u32,
    interrupt_status: u32,
    reserved2: u64,
    wall_clock_counter: u32,
    reserved3: u32,
    stream_sync: u32,
    reserved4: u32,
    corb: Corb,
    rirb: Rirb,

    immediate_command_output: u32,
    immediate_command_input: u32,
    immediate_command_status: u16,
    reserved5: u48,

    dma_position_base: u64,

    /// Command output ring buffer(Corb)
    const Corb = packed struct(u128) {
        corb_base: u64,
        corb_writer_ptr: u16,
        corb_read_ptr: u16,
        corb_ctrl: u8,
        corb_status: u8,
        corb_size: u8,
        reserved: u8,

        pub fn set_corb(self: *volatile @This(), value: u64) void {
            self.corb_base = value;
        }
    };

    /// Response input ring buffer(Rirb)
    const Rirb = packed struct(u128) {
        rirb_base: u64,
        rirb_writer_ptr: u16,
        response_interrupt_count: u16,
        rirb_ctrl: u8,
        rirb_status: u8,
        rirb_size: u8,
        reserved: u8,

        pub fn set_rirb(self: *volatile @This(), value: u64) void {
            self.rirb_base = value;
        }
    };

    const GlobalCapabilities = packed struct(u16) {
        is_64bits: bool,
        // sdo = serial data out signals
        sdo_count: u2,
        bidirection_stream_count: u5,
        input_stream_count: u4,
        output_stream_count: u4,
    };

    pub fn init_corb(self: *volatile @This()) !void {
        const corb_size = self.corb.corb_size;
        if (corb_size & (1 << 6) == (1 << 6)) {
            self.corb.corb_size |= 0b10;
        } else if (corb_size & (1 << 5) == (1 << 5)) {
            self.corb.corb_size |= 0b1;
        }

        const addr = try pmm.alloc(1);

        self.corb.set_corb(@intFromPtr(addr));
    }

    pub fn init_rirb(self: *volatile @This()) !void {
        const rirb_size = self.rirb.rirb_size;
        if (rirb_size & (1 << 6) == (1 << 6)) {
            self.rirb.rirb_size |= 0b10;
        } else if (rirb_size & (1 << 5) == (1 << 5)) {
            self.rirb.rirb_size |= 0b1;
        }

        const addr = try pmm.alloc(1);

        self.rirb.set_rirb(@intFromPtr(addr));
    }

    pub fn init_dma(self: *volatile @This()) !void {
        const addr = try pmm.alloc(1);
        self.dma_position_base = @intFromPtr(addr);
    }

    pub fn start_corb(self: *volatile @This()) void {
        self.corb.corb_ctrl |= (1 << 1);
    }

    pub fn start_rirb(self: *volatile @This()) void {
        self.rirb.rirb_ctrl |= (1 << 1);
    }
};

const IntelHda = struct {
    pci: *pci.PciDevice,
    register: *volatile HdaRegister,
};

pub fn init(device: *const pci.PciDevice) !void {
    device.set_master_flag();

    switch (device.bar(0).?) {
        .Mmio32 => |bar| {
            const mmio = bar.mmio;

            _ = device.capabilities();

            const hda_register: *volatile HdaRegister = @ptrFromInt(mmio.virt_addr);

            hda_register.global_ctrl.reset();

            if (!hda_register.global_caps.is_64bits) {
                @panic("Unsupported 32-bit HDA");
            }
            try hda_register.init_corb();
            try hda_register.init_rirb();
            try hda_register.init_dma();

            hda_register.start_corb();
            hda_register.start_rirb();

            hda_register.interrupt_ctrl |= 0xFF;

            for (0..hda_register.global_caps.output_stream_count) |_| {}

            for (0..hda_register.global_caps.input_stream_count) |_| {}

            serial.println("{any}", .{hda_register});
        },
        else => @panic("Unsupported"),
    }
}
