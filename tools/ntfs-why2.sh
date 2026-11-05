#!/bin/sh
CU=$(stat -f %u /dev/console); CG=$(id -g "$CU" 2>/dev/null || echo 20)
echo "=== 数据卷完整输出 ==="
mp=$(mount | grep "^/dev/disk0s6 " | sed 's/.* on \(.*\) (ntfs.*/\1/')
echo "挂载点: $mp"
diskutil unmount "$mp" 2>&1
sleep 1
SUDO_UID=$CU SUDO_GID=$CG /sbin/fsck_fskit -t ntfs4mac -n /dev/disk0s6 2>&1 | head -40
echo "exit=$?"
diskutil mount /dev/disk0s6 2>&1
