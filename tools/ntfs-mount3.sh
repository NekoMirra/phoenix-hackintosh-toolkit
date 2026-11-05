#!/bin/sh
echo "== ntfs4mac.fs Info.plist 关键键 =="
plutil -p /Library/Filesystems/ntfs4mac.fs/Contents/Info.plist 2>&1 | head -25
echo
echo "== 重启 fskitd =="
launchctl kickstart -k system/com.apple.fskitd 2>&1 || killall fskitd 2>&1
sleep 3
for t in ntfs4mac NTFS4Mac ntfs; do
  diskutil unmount /Volumes/系统 >/dev/null 2>&1; sleep 1
  echo "--- -t $t ---"
  /sbin/mount -F -t "$t" -o remove_hiberfile /dev/disk0s2 /Volumes/系统 2>&1
  sleep 2
  mount | grep disk0s2 || echo "  (未挂载)"
done
