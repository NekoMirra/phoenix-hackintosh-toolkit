#!/bin/sh
CU=$(stat -f %u /dev/console); CG=$(id -g "$CU" 2>/dev/null || echo 20)
check() {
  dev=$1; name=$2
  mp=$(mount | grep "^$dev " | sed 's/.* on \(.*\) (ntfs.*/\1/')
  echo "===== $name ($dev) ====="
  [ -n "$mp" ] && { diskutil unmount "$mp" >/dev/null 2>&1; sleep 1; }
  SUDO_UID=$CU SUDO_GID=$CG /sbin/fsck_fskit -t ntfs4mac -n "$dev" 2>&1 | grep -iE "hibernat|dirty|clean|complete" | sed 's/^/  /'
  diskutil mount "$dev" >/dev/null 2>&1; sleep 1
  mount | grep "^$dev " | sed 's/^/  /'
}
check /dev/disk0s6 "数据"
check /dev/disk1s1 "MirraAI"
