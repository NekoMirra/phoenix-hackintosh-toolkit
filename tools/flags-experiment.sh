#!/bin/sh
OFF=$((3221228544 + 0x16A))
echo "== 当前值 =="
dd if=/dev/rdisk0s2 bs=1 skip=$OFF count=2 2>/dev/null | xxd
echo "== 备份并写入 0x0080 =="
dd if=/dev/rdisk0s2 bs=1 skip=$OFF count=2 2>/dev/null of=/tmp/volflags.bak
printf '\200\000' | dd of=/dev/rdisk0s2 bs=1 seek=$OFF conv=notrunc 2>&1
sync
echo "== 读回 =="
dd if=/dev/rdisk0s2 bs=1 skip=$OFF count=2 2>/dev/null | xxd
echo "== 重挂 系统 卷 =="
diskutil unmount /Volumes/系统 >/dev/null 2>&1; sleep 1
diskutil mount /dev/disk0s2 >/dev/null 2>&1; sleep 2
mount | grep disk0s2
log show --last 40s --info --predicate 'process == "NTFSExtension"' 2>&1 | grep "probe disk0s2" | tail -2
