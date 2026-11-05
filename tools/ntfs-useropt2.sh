#!/bin/sh
for opt in "rw,remove_hiberfile" "remove_hiberfile,rw" "rw" "repair"; do
  diskutil unmount /Volumes/系统 >/dev/null 2>&1
  sleep 1
  echo "--- 选项: $opt ---"
  out=$(diskutil mount -mountOptions "$opt" /dev/disk0s2 2>&1)
  echo "$out"
  sleep 2
  m=$(mount | grep disk0s2)
  echo "$m"
  echo "$m" | grep -q read-only || echo "  >>> 可读写 <<<"
done
