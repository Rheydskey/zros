#!/bin/bash

zig build $1

test $? -eq 0 || exit;

bash ./scripts/makeiso.sh
qemu-system-x86_64 -serial stdio -drive format=raw,file=zros.hdd -no-reboot -no-shutdown #-d int,cpu_reset,in_asm
