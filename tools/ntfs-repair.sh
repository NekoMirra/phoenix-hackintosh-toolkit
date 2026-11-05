#!/bin/sh
# 对单个 NTFS 卷做「先检查、再修复、后重挂」
# 用法: ntfs-repair.sh /dev/disk0s2 系统 [--fix]
set -u
DEV="$1"
NAME="$2"
FIX="${3:-}"
CUID=$(stat -f %u /dev/console)
CGID=$(id -g "$CUID" 2>/dev/null || echo 20)

MP=$(mount | grep "^$DEV " | sed 's/.* on \(.*\) (ntfs.*/\1/')

echo "===== $NAME ($DEV) ====="
if [ -n "$MP" ]; then
    echo "-- 卸载 $MP --"
    diskutil unmount "$MP" 2>&1 || { echo "!! 卸载失败，跳过"; exit 1; }
    sleep 1
fi

echo "-- 只读检查 fsck -n --"
SUDO_UID=$CUID SUDO_GID=$CGID /sbin/fsck_fskit -t ntfs4mac -n "$DEV" 2>&1 | tail -20
echo "check-exit=$?"

if [ "$FIX" = "--fix" ]; then
    echo "-- 修复 fsck -y --"
    SUDO_UID=$CUID SUDO_GID=$CGID /sbin/fsck_fskit -t ntfs4mac -y "$DEV" 2>&1 | tail -25
    echo "fix-exit=$?"
fi

echo "-- 重新挂载 --"
diskutil mount "$DEV" 2>&1
sleep 2
mount | grep "^$DEV " || echo "!! 未挂上"
