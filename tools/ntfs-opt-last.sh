#!/bin/sh
echo "== fstab 是否已清理 =="; ls -la /etc/fstab 2>&1
echo
echo "== 尝试 -mountOptions 字面传 -o remove_hiberfile =="
diskutil unmount /Volumes/系统 >/dev/null 2>&1; sleep 1
diskutil mount -mountOptions "-o remove_hiberfile" /dev/disk0s2 2>&1
sleep 2
mount | grep disk0s2
echo
echo "== 再试 rw,remove_hiberfile,force =="
diskutil unmount /Volumes/系统 >/dev/null 2>&1; sleep 1
diskutil mount -mountOptions "rw,remove_hiberfile,force" /dev/disk0s2 2>&1
sleep 2
mount | grep disk0s2
