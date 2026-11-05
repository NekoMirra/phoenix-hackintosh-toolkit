#!/bin/sh
# 精确定位 ntfs4mac 挂载失败原因：重启用户域 fskitd + 抓失败瞬间日志
set -u
DEV="${1:-/dev/disk3s1}"
MP="${2:-/Volumes/Ventoy}"
CUID=$(stat -f %u /dev/console)
CGID=$(id -g "$CUID" 2>/dev/null || echo 20)

echo "== 用户域 fskitd 服务 =="
launchctl print "gui/$CUID/com.apple.fskitd" 2>&1 | head -5
echo "-- kickstart --"
launchctl kickstart -k "gui/$CUID/com.apple.fskitd" 2>&1
sleep 3

echo "== 卸载 =="
diskutil unmount force "$MP" >/dev/null 2>&1
sleep 1

echo "== 尝试挂载（拿完整错误）=="
T0=$(date "+%Y-%m-%d %H:%M:%S")
SUDO_UID=$CUID SUDO_GID=$CGID /sbin/mount -F -t ntfs4mac -o rw "$DEV" "$MP" 2>&1
echo "exit=$?"
sleep 2

echo "== 失败瞬间日志（fskit / extensionkit）=="
log show --start "$T0" --predicate 'process == "fskitd" OR process == "fskit_agent" OR process == "fskit_helper" OR subsystem == "com.apple.FSKit" OR subsystem == "com.apple.ExtensionKit"' 2>&1 | grep -viE "lifs_|retrying lookup" | tail -25

echo "== 兜底恢复 =="
if ! mount | grep -q "^$DEV"; then
  diskutil mount "$DEV" >/dev/null 2>&1
fi
mount | grep "$DEV"
