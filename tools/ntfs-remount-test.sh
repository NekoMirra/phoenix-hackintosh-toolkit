#!/bin/sh
# 用 ntfs4mac FSKit 扩展重新挂载指定卷，验证读写能力
# 用法: ntfs-remount-test.sh /dev/disk3s1 /Volumes/Ventoy
set -u
DEV="$1"
MP="$2"
CUID=$(stat -f %u /dev/console)
CGID=$(id -g "$CUID" 2>/dev/null || echo 20)

echo "== 控制台用户 uid=$CUID gid=$CGID =="
echo "== 卸载 $MP =="
diskutil unmount force "$MP" 2>&1 || echo "unmount failed"
sleep 1
mkdir -p "$MP"

echo "== 用 ntfs4mac 模块挂载 =="
SUDO_UID=$CUID SUDO_GID=$CGID /sbin/mount -F -t ntfs4mac -o rw "$DEV" "$MP" 2>&1
echo "mount exit=$?"

sleep 1
echo "== 挂载结果 =="
mount | grep -i "$DEV" || echo "未挂载"
echo "== 写测试 =="
if touch "$MP/.wtest_ntfs" 2>/dev/null; then
  echo "WRITE_OK 扩展工作正常"
  rm -f "$MP/.wtest_ntfs"
else
  echo "WRITE_FAIL 仍然只读"
fi
