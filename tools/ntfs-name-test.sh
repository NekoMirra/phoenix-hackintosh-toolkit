#!/bin/sh
# 测试 mount 的文件系统名解析：ntfs4mac vs NTFS4Mac vs 走 .fs 辅助脚本
set -u
DEV="${1:-/dev/disk3s1}"
MP="${2:-/Volumes/Ventoy}"
CUID=$(stat -f %u /dev/console)
CGID=$(id -g "$CUID" 2>/dev/null || echo 20)

try() {
  label="$1"; shift
  diskutil unmount force "$MP" >/dev/null 2>&1
  sleep 1
  mkdir -p "$MP"
  echo "--- $label ---"
  if [ "$1" = "HELPER" ]; then
    SUDO_UID=$CUID SUDO_GID=$CGID /Library/Filesystems/ntfs4mac.fs/Contents/Resources/mount_ntfs4mac -o rw "$DEV" "$MP" 2>&1
  else
    SUDO_UID=$CUID SUDO_GID=$CGID /sbin/mount "$@" -o rw "$DEV" "$MP" 2>&1
  fi
  echo "exit=$?"
  mount | grep "^$DEV" || echo "(未挂载)"
  if mount | grep -q "^$DEV"; then diskutil unmount force "$MP" >/dev/null 2>&1; fi
}

try "A: -F -t ntfs4mac"       -F -t ntfs4mac
try "B: -F -t NTFS4Mac"       -F -t NTFS4Mac
try "C: -t ntfs4mac (无 -F)"  -t ntfs4mac
try "D: 官方辅助脚本"          HELPER
try "E: -F -t ntfs (苹果模块基准)" -F -t ntfs

echo "===== 恢复默认 ====="
if ! mount | grep -q "^$DEV"; then diskutil mount "$DEV" >/dev/null 2>&1; fi
mount | grep "$DEV"
