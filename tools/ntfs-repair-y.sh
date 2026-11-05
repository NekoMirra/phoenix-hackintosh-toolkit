#!/bin/sh
CU=$(stat -f %u /dev/console); CG=$(id -g "$CU" 2>/dev/null || echo 20)
echo "== 卸载 系统 =="
diskutil unmount /Volumes/系统 2>&1
sleep 1
echo "== fsck_fskit -y（官方修复路径）=="
SUDO_UID=$CU SUDO_GID=$CG /sbin/fsck_fskit -t ntfs4mac -y /dev/disk0s2 2>&1 | head -40
echo "exit=$?"
echo "== 挂载并检查 =="
diskutil mount /dev/disk0s2 2>&1
sleep 2
mount | grep disk0s2 || echo "(未挂载)"
