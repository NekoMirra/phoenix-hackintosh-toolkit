#!/bin/sh
diskutil unmount /Volumes/系统 >/dev/null 2>&1; sleep 1
echo "== A: mount -F -t ntfs4mac -o remove_hiberfile =="
/sbin/mount -F -t ntfs4mac -o remove_hiberfile /dev/disk0s2 /Volumes/系统 2>&1; echo "exit=$?"
sleep 2; mount | grep disk0s2 || echo "(未挂载)"
echo
echo "== B: 直接调辅助脚本 =="
diskutil unmount /Volumes/系统 >/dev/null 2>&1; sleep 1
/Library/Filesystems/ntfs4mac.fs/Contents/Resources/mount_ntfs4mac -o remove_hiberfile /dev/disk0s2 /Volumes/系统 2>&1; echo "exit=$?"
sleep 2; mount | grep disk0s2 || echo "(未挂载)"
