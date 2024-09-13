#!/bin/env bash

export DEBUG=0
export KVM=0
export GDB=0


zig build $1

test $? -eq 0 || exit;

bash ./meta/scripts/makeiso.sh

if [ -f "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd" ]
then
  file="/usr/share/edk2-ovmf/x64/OVMF_CODE.fd"
else
  file="/usr/share/edk2-ovmf/OVMF_CODE.fd"
fi

export ARGS="-serial mon:stdio \
                   -drive format=raw,file=zros.hdd \
                   -no-reboot \
                   -no-shutdown \
                   -m 1024M \
                   -M q35 \
                   -smp 4 \
                   -bios $file"

if [[ $DEBUG -eq 1 ]]
then
export ARGS="$ARGS -d int,cpu_reset,in_asm"
fi


if [[ $KVM -eq 1 ]]
then
export ARGS="$ARGS -enable-kvm"
fi


if [[ $GDB -eq 1 ]]
then
export ARGS="$ARGS -s -S"
fi

echo $ARGS

qemu-system-x86_64 $ARGS
