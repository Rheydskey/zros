// https://osdev.wiki/wiki/AHCI
// https://www.intel.com/content/dam/www/public/us/en/documents/technical-specifications/serial-ata-ahci-spec-rev1_1.pdf
// https://github.com/BlueGummi/charmos/blob/main/kernel/drivers/ahci/init.c
const pci = @import("./pci.zig");
const serial = @import("./serial.zig");

const FisType = struct {
    /// Register FIS - host to device
    const REG_H2D = 0x27;

    /// Register FIS - device to host
    const REG_D2H = 0x34;

    /// DMA activate FIS - device to host
    const DMA_ACT = 0x39;

    /// DMA setup FIS - bidirectional
    const DMA_SETUP = 0x41;

    /// Data FIS - bidirectional
    const DATA = 0x46;

    /// BIST activate FIS - bidirectional
    const BIST = 0x58;

    /// PIO setup FIS - device to host
    const PIO_SETUP = 0x5F;

    /// Set device bits FIS - device to host
    const DEV_BITS = 0xA1;
};

const Tag = struct {
    const Reg_H2D = packed struct {
        const FeaturesRegister = struct {};

        // Should be FisType.REG_H2D
        fis_type: u8,

        /// Port multiplier
        pmport: u4,
        rsv0: u3,
        c: u1,

        status_reg: u8,
        error_reg: u8,

        lba0: u8,
        lba1: u8,
        lba2: u8,
        /// Device register
        device: u8,

        lba3: u8,
        lba4: u8,
        lba5: u8,
        feature: FeaturesRegister,

        /// Count low
        countl: u8,
        counth: u8,
        /// Isochronous command completion
        icc: u8,
        control: u8,
        rsv1: u32,
    };

    const Reg_D2H = packed struct {
        // Should be FisType.REG_H2D
        fis_type: u8,

        /// Port multiplier
        pmport: u4,
        rsv0: u3,
        /// Interrupt bit
        i: u1,
        rsv1: u1,

        status_reg: u8,
        error_reg: u8,

        lba0: u8,
        lba1: u8,
        lba2: u8,
        /// Device register
        device: u8,

        lba3: u8,
        lba4: u8,
        lba5: u8,
        rsv2: u8,

        /// Count low
        countl: u8,
        counth: u8,

        rsv4: u48,
    };

    const FisData = packed struct(u64) {
        fis_type: u8,

        /// Port multiplier
        pmport: u4,
        rsv0: u20,

        /// Payload
        data: u32,
    };

    const FisPioSetup = packed struct {
        // Should be FisType.REG_H2D
        fis_type: u8,

        /// Port multiplier
        pmport: u4,
        rsv0: u1,
        d: u1,
        /// Interrupt bit
        i: u1,
        rsv1: u1,

        status_reg: u8,
        error_reg: u8,

        lba0: u8,
        lba1: u8,
        lba2: u8,
        /// Device register
        device: u8,

        lba3: u8,
        lba4: u8,
        lba5: u8,
        rsv2: u8,

        /// Count low
        countl: u8,
        counth: u8,
        rsv3: u8,
        e_status: u8,

        transfer_count: u16,
        rsv4: u16,
    };

    const FisDmaSetup = struct {
        pub const Direction = enum(u1) {
            HostToDevice,
            DeviceToHost,
        };

        fis_type: u8,
        pmport: u4,
        rsv0: u1,

        d: Direction,
        i: u1,

        /// Auto-activate. Specifies if DMA Activate FIS is neeeded
        a: u1,

        rsv1: u16,

        dma_buffer_id: u64,
        rsv2: u32,
        dma_buffer_offset: u32,
        transfer_count: u32,
        rsv3: u32,
    };

    const HbaPort = packed struct {
        clb: u64,
        fb: u64,

        /// Interrupt status
        is: u32,

        // Interrupt enable
        ie: u32,

        cmd: u32,
        rsv0: u32,
        /// Task file data
        tfd: u32,
        sig: u32,
        sata_status: u32,
        sata_ctl: u32,
        sata_err: u32,
        sata_active: u32,

        // Command issue
        ci: u32,
        sata_notif: u32,
        fbs: u32,
        rsv1: u352,
        vendor: u128,

        const START: u32 = 1 << 0;
        const FIS_RECEIVE_ENABLE: u32 = (1 << 4);
        const AHCI_DET_PRESENT: u32 = 0x3;
        const AHCI_IPM_ACTIVE: u32 = 0x1;
    };

    const HbaMem = packed struct {
        // GHC CONSTANT
        const ENABLE_AHCI: u32 = (1 << 31);
        // GHC CONSTANT
        const ENABLE_INTERRUPT: u32 = (1 << 1);

        cap: u32,
        ghc: u32,
        is: u32,
        pi: u32,
        vs: u32,
        ccc_ctl: u32,
        ccc_pts: u32,
        em_loc: u32,
        em_ctl: u32,
        cap2: u32,
        bohc: u32,
        rsv: u116,
        vendor: u69,
        port: HbaPort,
    };
};

pub fn init_port(mem: *volatile Tag.HbaMem) !void {
    const pi = mem.pi;

    if (pi & (1 << 1) == 0) {
        return;
    }

    mem.port.cmd &= ~Tag.HbaPort.START; // FIXME: Remove magic value
    @import("./hpet.zig").hpet.?.sleep(1000);
    // if (port.cmd & (1 << 15) == 0) @panic("Command list not running");

    mem.port.cmd &= ~Tag.HbaPort.FIS_RECEIVE_ENABLE; // FIXME: Remove magic value
    @import("./hpet.zig").hpet.?.sleep(5000);
    // if (port.cmd & (1 << 14) == 0) @panic("FIS not running");

    mem.port.cmd |= Tag.HbaPort.START | Tag.HbaPort.FIS_RECEIVE_ENABLE;

    const det = mem.port.sata_status & 0x0F;
    const ipm = (mem.port.sata_status >> 8) & 0x0F;
    if (det != Tag.HbaPort.AHCI_DET_PRESENT or ipm != Tag.HbaPort.AHCI_IPM_ACTIVE) {
        serial.println("Neither AHCI_DET_PRESENT or AHCI_IPM_ACTIVE is present", .{});
        return;
    }

    serial.println("Sig: {b}", .{mem.port.sig});
}

// Interrupt of AHCI = 127
pub fn init(device: *pci.PciDevice) !void {
    const bar = device.bar(5) orelse {
        return error.NoBar;
    };

    switch (bar) {
        .Mmio32 => |mmio| {
            const hba: *volatile Tag.HbaMem = @ptrFromInt(mmio.mmio.virt_addr);
            serial.println("{any}", .{hba});
            if (hba.cap & (1 << 31) == 0) {
                return error.No64bitSupport;
            }

            hba.ghc = 1; // FIXME: Remove magic value: Reset controller
            @import("./hpet.zig").hpet.?.sleep(5000);
            serial.println("GHB: {b}", .{hba.ghc});
            hba.ghc |= Tag.HbaMem.ENABLE_AHCI;

            serial.println("{any}", .{hba});

            // const port = hba.ports;
            // const ipm = (port.sata_status >> 8) & 0x0F;
            // const det =
            hba.ghc |= Tag.HbaMem.ENABLE_INTERRUPT;
            try init_port(hba);
        },
        else => {
            return error.Unsupported;
        },
    }
}
