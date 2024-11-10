// https://osdev.wiki/wiki/AHCI

const Ahci = struct {
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
};
