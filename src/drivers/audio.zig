const pci = @import("./pci.zig");
const rq = @import("../limine_rq.zig");
const serial = @import("./serial.zig");
const pmm = @import("../mem/pmm.zig");

// https://osdev.wiki/wiki/Intel_High_Definition_Audio#Device_Registers
// https://www.intel.com/content/dam/www/public/us/en/documents/product-specifications/high-definition-audio-specification.pdf
const HdaRegister = packed struct {
    /// Command output ring buffer(Corb)
    const Corb = packed struct(u128) {
        corb_lower_base: u32,
        corb_upper_base: u32,
        corb_writer_ptr: u16,
        corb_read_ptr: u16,
        corb_ctrl: u8,
        corb_status: u8,
        corb_size: u8,
        reserved: u8,

        pub fn set_corb(self: *volatile @This(), value: u64) void {
            self.corb_lower_base = @intCast(value & 0xFFFF_FFFF);
            self.corb_upper_base = @intCast(value >> 32 & 0xFFFF_FFFF);
        }
    };

    /// Response input ring buffer(Rirb)
    const Rirb = packed struct(u128) {
        rirb_lower_base: u32,
        rirb_upper_base: u32,
        rirb_writer_ptr: u16,
        response_interrupt_count: u16,
        rirb_ctrl: u8,
        rirb_status: u8,
        rirb_size: u8,
        reserved: u8,

        pub fn set_rirb(self: *volatile @This(), value: u64) void {
            self.rirb_lower_base = @intCast(value & 0xFFFF_FFFF);
            self.rirb_upper_base = @intCast(value >> 32 & 0xFFFF_FFFF);
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
            self.controller_reset = 0;
        }

        pub fn is_in_reset_state(self: *volatile @This()) bool {
            return self.controller_reset == 0;
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

    dma_position_lower_base: u32,
    dma_position_upper_base: u32,
};

const IntelHda = struct {
    pci: *pci.Pci,

    register: *HdaRegister,
};

pub fn init(device: *const pci.PciDevice) !void {
    device.set_master_flag();

    switch (device.bar(0).?) {
        .Mmio32 => |bar| {
            const mmio = bar.mmio;

            serial.println("{X}, PTR: {X} mmio: {x}", .{ bar.base, bar.base + rq.hhdm.response.?.offset, mmio.virt_addr });

            const hda_register: *volatile HdaRegister = @ptrFromInt(mmio.virt_addr);

            serial.println("{any}", .{hda_register});

            hda_register.global_ctrl.reset();
            while (hda_register.global_ctrl.is_in_reset_state()) {}

            serial.println("Reseted", .{});

            @import("../drivers/hpet.zig").hpet.?.sleep(1);

            if (!hda_register.global_caps.is_64bits) {
                @panic("Unsupported 32-bit HDA");
            }

            // FIXME: use correct value
            hda_register.corb.corb_size = 2;
            hda_register.rirb.rirb_size = 2;

            const corb_phys = try pmm.alloc_page(1);
            const rirb_phys = try pmm.alloc_page(1);
            // const dma_phys = try pmm.alloc_page(1);
            hda_register.corb.set_corb(@intFromPtr(corb_phys));
            hda_register.rirb.set_rirb(@intFromPtr(rirb_phys));

            serial.println("{any}", .{hda_register});
        },
        else => @panic("Unsupported"),
    }
}
