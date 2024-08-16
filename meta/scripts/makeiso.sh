#!/bin/bash

PWD=$(pwd)

KERNEL_HDD="$PWD/zros.hdd"

rm -rvf "$PWD/iso_root"

mkdir -p "$PWD/iso_root"

cp -v "$PWD/zig-out/bin/zros" "$PWD/bin/limine.conf" "$PWD/limine/limine-bios.sys" "$PWD/limine/limine-bios-cd.bin" "$PWD/limine/limine-uefi-cd.bin" "$PWD/iso_root/"

xorriso -as mkisofs -b limine-bios-cd.bin \
-no-emul-boot -boot-load-size 4 -boot-info-table \
--efi-boot limine-uefi-cd.bin \
-efi-boot-part --efi-boot-image --protective-msdos-label \
iso_root -o ${KERNEL_HDD}

$PWD/limine/limine bios-install ${KERNEL_HDD}
