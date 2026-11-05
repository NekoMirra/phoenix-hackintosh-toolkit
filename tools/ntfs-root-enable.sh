#!/bin/sh
SRC="/Users/mirra/Library/Group Containers/group.com.apple.fskit.settings"
DST="/var/root/Library/Group Containers/group.com.apple.fskit.settings"
echo "== 创建 root 容器 =="
mkdir -p "$DST"
cp "$SRC/enabledModules.plist" "$DST/" 2>&1
cp "$SRC/probeOrder.plist" "$DST/" 2>&1
chown -R root:wheel "$DST"
ls -la "$DST"
echo
echo "== 卸载 系统 =="
diskutil unmount /Volumes/系统 2>&1
sleep 1
echo "== mount -F -t ntfs4mac -o remove_hiberfile =="
/sbin/mount -F -t ntfs4mac -o remove_hiberfile /dev/disk0s2 /Volumes/系统 2>&1
echo "exit=$?"
sleep 2
mount | grep disk0s2 || echo "(未挂载)"
