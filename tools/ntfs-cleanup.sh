#!/bin/sh
echo "== 删除测试用 fstab =="
rm -f /etc/fstab /etc/fstab.bak
ls -la /etc/fstab 2>&1
echo "== 重新挂载系统卷 =="
diskutil mount /dev/disk0s2 2>&1
sleep 2
echo "== 全部 NTFS 挂载状态 =="
mount | grep '(ntfs'
