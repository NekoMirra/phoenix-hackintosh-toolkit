#!/bin/sh
cd /Users/mirra/WorkBuddy/2026-11-03-20-03-17/tools
echo "== 卸载 系统 =="
diskutil unmount /Volumes/系统 2>&1
sleep 1
echo "== 设为 0x0080（等同 Ventoy）=="
./ntfsdirty set /dev/rdisk0s2 0x0080 2>&1
echo "== 重挂 =="
diskutil mount /dev/disk0s2 >/dev/null 2>&1; sleep 3
mount | grep disk0s2
log show --last 30s --info --predicate 'process == "NTFSExtension"' 2>&1 | grep "probe disk0s2" | tail -2
