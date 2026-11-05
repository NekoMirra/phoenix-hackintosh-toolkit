#!/bin/sh
echo "== 主记录3 -> 镜像记录3 =="
dd if=/dev/rdisk0s2 bs=512 skip=6291462 count=2 2>/dev/null | dd of=/dev/rdisk0s2 bs=512 seek=22 conv=notrunc 2>&1
sync
echo "== 校验镜像 =="
dd if=/dev/rdisk0s2 bs=512 skip=22 count=2 2>/dev/null | xxd -s 0x160 -l 16
echo "== 挂载 =="
diskutil mount /dev/disk0s2 2>&1
sleep 3
mount | grep disk0s2 || echo "(仍未挂载)"
echo "== 写测试 =="
touch /Volumes/系统/.wtest_mac 2>&1 && echo "WRITE_OK ✅" && rm -f /Volumes/系统/.wtest_mac || echo "仍只读"
