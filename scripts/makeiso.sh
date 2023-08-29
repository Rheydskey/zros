#!/bin/bash

KERNEL_HDD="zros.hdd"

mkdir -p iso_root

cp -v ./zig-out/bin/zros bin/limine.cfg limine/limine-bios.sys limine/limine-bios-cd.bin limine/limine-uefi-cd.bin iso_root/

xorriso -as mkisofs -b limine-bios-cd.bin \
-no-emul-boot -boot-load-size 4 -boot-info-table \
--efi-boot limine-uefi-cd.bin \
-efi-boot-part --efi-boot-image --protective-msdos-label \
iso_root -o ${KERNEL_HDD}

./limine/limine bios-install ${KERNEL_HDD}