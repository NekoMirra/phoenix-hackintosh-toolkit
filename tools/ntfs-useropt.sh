#!/bin/sh
for opt in "force" "remove_hiberfile" "rw,force" "nobrowse"; do
  diskutil unmount /Volumes/系统 >/dev/null 2>&1
  sleep 1
  echo "--- 选项: $opt ---"
  diskutil mount -mountOptions "$opt" /dev/disk0s2 2>&1
  sleep 2
  mount | grep disk0s2 || echo "  (未挂载)"
done
