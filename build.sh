#!/bin/bash

zig build
bash ./scripts/makeiso.sh
qemu-system-x86_64 -serial stdio -drive format=raw,file=zros.hdd -s -S