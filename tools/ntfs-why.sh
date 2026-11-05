#!/bin/sh
CU=$(stat -f %u /dev/console); CG=$(id -g "$CU" 2>/dev/null || echo 20)
for spec in "/dev/disk0s2 系统" "/dev/disk0s6 数据" "/dev/disk2s1 MirraAI"; do
  set -- $spec; dev=$1; name=$2
  echo "===== $name ($dev) ====="
  mp=$(mount | grep "^$dev " | sed 's/.* on \(.*\) (ntfs.*/\1/')
  [ -n "$mp" ] && diskutil unmount "$mp" >/dev/null 2>&1
  sleep 1
  SUDO_UID=$CU SUDO_GID=$CG /sbin/fsck_fskit -t ntfs4mac -n "$dev" 2>&1 | grep -iE "hibernat|dirty|clean|WARNING|check:|CLEAN" | sed 's/^/  /'
  diskutil mount "$dev" >/dev/null 2>&1
done
