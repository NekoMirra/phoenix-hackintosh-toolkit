#!/bin/sh
echo "== mount 用法中的 -F =="
mount 2>&1 | head -6
echo
echo "== 卸载 系统 卷 =="
diskutil unmount /Volumes/系统 2>&1
sleep 1
echo "== 用 mount -t ntfs4mac + remove_hiberfile =="
/sbin/mount -t ntfs4mac -o remove_hiberfile /dev/disk0s2 /Volumes/系统 2>&1
echo "exit=$?"
sleep 2
mount | grep disk0s2 || echo "(未挂载)"
