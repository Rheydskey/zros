// https://osdev.wiki/wiki/AHCI

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
        rsv1: u20,

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

        rsv0: u16,

        dma_buffer_id: u64,
        rsv1: u32,
        dma_buffer_offset: u32,
        transfer_count: u32,
        rsv2: u32,
    };
};
