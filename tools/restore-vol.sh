#!/bin/sh
cd /Users/mirra/WorkBuddy/2026-11-03-20-03-17/tools
echo "== 卸载 =="
diskutil unmount /Volumes/系统 2>&1
sleep 1
echo "== 恢复 flags=0x0000 =="
./ntfsdirty set /dev/rdisk0s2 0x0000 2>&1 | tail -4
echo "== 同步到 MFT 镜像 =="
dd if=/dev/rdisk0s2 bs=512 skip=6291462 count=2 2>/dev/null | dd of=/dev/rdisk0s2 bs=512 seek=22 conv=notrunc 2>&1
sync
echo "== 与备份逐字节比对 =="
dd if=/dev/rdisk0s2 bs=512 skip=6291462 count=2 2>/dev/null > /tmp/now.rec
cmp /tmp/now.rec ntfs-volume-3145731.bak && echo "完全一致 ✅" || echo "有差异 ⚠️"
echo "== 挂载 =="
diskutil mount /dev/disk0s2 2>&1
sleep 2
mount | grep disk0s2 || echo "(未挂载)"
echo "== 目录抽样 =="
ls /Volumes/系统 2>/dev/null | head -5
