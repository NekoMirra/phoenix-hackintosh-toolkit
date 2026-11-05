#!/bin/sh
# 诊断为什么 ntfs4mac 模块被判为 invalid file system
set -u
DEV="${1:-/dev/disk3s1}"
MP="${2:-/Volumes/Ventoy}"
CUID=$(stat -f %u /dev/console)
CGID=$(id -g "$CUID" 2>/dev/null || echo 20)

echo "== 1. 重启 fskitd（让它重读 enabledModules.plist）=="
launchctl kickstart -k system/com.apple.fskitd 2>&1 || killall -9 fskitd 2>&1
sleep 3

echo "== 2. 重新探测卷 =="
diskutil list "$DEV" 2>&1 | head -5
echo "-- personality 探测 --"
/usr/libexec/ntfs.util -p "$DEV" 2>&1 | head -3 || true

echo "== 3. 再次用 ntfs4mac 挂载 =="
mkdir -p "$MP"
SUDO_UID=$CUID SUDO_GID=$CGID /sbin/mount -F -t ntfs4mac -o rw "$DEV" "$MP" 2>&1
echo "exit=$?"

echo "== 4. 相关日志 =="
log show --last 2m --predicate 'process == "fskitd" OR process == "fskit_helper" OR eventMessage CONTAINS "ntfs4mac" OR eventMessage CONTAINS "NTFSExtension"' 2>&1 | tail -25

echo "== 5. 兜底：如果没挂上就恢复默认只读挂载 =="
if ! mount | grep -q "$DEV"; then
  diskutil mount "$DEV" 2>&1 | head -3
  mount | grep "$DEV"
fi
