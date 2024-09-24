#!/bin/env bash

export DEBUG=0
export KVM=1
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
                   -device ich9-intel-hda,id=sound0,bus=pcie.0,addr=0x1b -device hda-duplex,id=sound0-codec0,bus=sound0.0,cad=0 \
                   -global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1
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
