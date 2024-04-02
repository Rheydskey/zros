#!/bin/bash

zig build $1

test $? -eq 0 || exit;

bash ./meta/scripts/makeiso.sh
qemu-system-x86_64 -serial stdio \
                   -drive format=raw,file=zros.hdd \
                   -no-reboot \
                   -no-shutdown \
                   -m 1024M \
                   -M q35 \
                   -smp 1 \
                   -bios /usr/share/ovmf/x64/OVMF.fd
                   #-d int,cpu_reset,in_asm
