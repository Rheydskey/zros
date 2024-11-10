const pci = @import("./pci.zig");
const rq = @import("../limine_rq.zig");
const serial = @import("./serial.zig");

// https://osdev.wiki/wiki/Intel_High_Definition_Audio#Device_Registers
// https://www.intel.com/content/dam/www/public/us/en/documents/product-specifications/high-definition-audio-specification.pdf
const HdaRegister = packed struct {
    const Corb = packed struct(u128) {
        corb_lower_base: u32,
        corb_upper_base: u32,
        corb_writer_ptr: u16,
        corb_read_ptr: u16,
        corb_ctrl: u8,
        corb_status: u8,
        corb_size: u8,
        reserved: u8,
    };

    const Rirb = packed struct {
        rirb_lower_base: u32,
        rirb_upper_base: u32,
        rirb_writer_ptr: u16,
        response_interrupt_count: u16,
        rirb_ctrl: u8,
        rirb_status: u8,
        rirb_size: u8,
        reserved: u8,
    };

    const GlobalCapabilities = packed struct(u16) {
        is_64bits: bool,
        // sdo = serial data out signals
        sdo_count: u2,
        bidirection_stream_count: u5,
        input_stream_count: u4,
        output_stream_count: u4,
    };

    global_caps: u16,
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

        pub fn reset(self: *@This()) void {
            self.controller_reset = 0;
        }

        pub fn is_in_reset_state(self: *@This()) bool {
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

pub fn init(device: *const pci.Pci, _: u16, _: u16) !void {
    const bar = (try device.bar(0)) orelse {
        return error.NoBar;
    };
    serial.println("{X}, PTR: {X}", .{ bar.base, bar.base + rq.hhdm.response.?.offset });

    const hda_register: *HdaRegister = @ptrFromInt(bar.base + rq.hhdm.response.?.offset);

    const phys_hda_register: *HdaRegister = @ptrFromInt(bar.base);

    serial.println("{any}", .{phys_hda_register});

    serial.println("{any}", .{hda_register});

    hda_register.global_ctrl.reset();
    while (hda_register.global_ctrl.is_in_reset_state()) {}

    serial.println("Reseted", .{});

    // hda_register.global_ctrl = hda_register.global_ctrl | 1;
    // while ((hda_register.global_ctrl & (1 << 0)) == 0) {
    //     asm volatile ("pause");
    // }

    @import("../drivers/hpet.zig").hpet.?.sleep(1);

    serial.println("{any}", .{hda_register});

    serial.println("{any}", .{phys_hda_register});
}
