#!/bin/sh
# 分离测试：ntfs4mac 只读挂载 vs 读写挂载
set -u
DEV="${1:-/dev/disk3s1}"
MP="${2:-/Volumes/Ventoy}"
CUID=$(stat -f %u /dev/console)
CGID=$(id -g "$CUID" 2>/dev/null || echo 20)

dolog() {
  log show --last 25s --predicate 'process == "NTFSExtension"' 2>&1 \
    | grep -viE "libxpc|lifs_|retrying lookup|BoardServices" | tail -18
}

echo "===== A. 只读挂载 ====="
diskutil unmount force "$MP" >/dev/null 2>&1; sleep 1
mkdir -p "$MP"
SUDO_UID=$CUID SUDO_GID=$CGID /sbin/mount -F -t ntfs4mac -o ro "$DEV" "$MP" 2>&1
echo "ro-exit=$?"
mount | grep "$DEV" || echo "(未挂载)"
dolog

echo
echo "===== B. 读写挂载 ====="
if mount | grep -q "^$DEV"; then diskutil unmount force "$MP" >/dev/null 2>&1; sleep 1; fi
SUDO_UID=$CUID SUDO_GID=$CGID /sbin/mount -F -t ntfs4mac -o rw "$DEV" "$MP" 2>&1
echo "rw-exit=$?"
mount | grep "$DEV" || echo "(未挂载)"
dolog

echo
echo "===== 恢复默认挂载 ====="
if ! mount | grep -q "^$DEV"; then diskutil mount "$DEV" >/dev/null 2>&1; fi
mount | grep "$DEV"
