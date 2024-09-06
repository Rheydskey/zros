#!/bin/bash

zig build $1

test $? -eq 0 || exit;

bash ./meta/scripts/makeiso.sh

if [ -f "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd" ]
then
  file="/usr/share/edk2-ovmf/x64/OVMF_CODE.fd"
else
  file="/usr/share/edk2-ovmf/OVMF_CODE.fd"
fi


qemu-system-x86_64 -serial mon:stdio \
                   -drive format=raw,file=zros.hdd \
                   -no-reboot \
                   -no-shutdown \
                   -m 1024M \
                   -M q35 \
                   -smp 4 \
                   -bios $file \
                   -enable-kvm
                   # -d int,cpu_reset,in_asm \
                   # -enable-kvm \
