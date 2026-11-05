#!/bin/sh
echo "== 卸载 系统 =="
diskutil unmount /Volumes/系统 2>&1
sleep 1
echo "== 带 remove_hiberfile 挂载 =="
diskutil mount -mountOptions remove_hiberfile /dev/disk0s2 2>&1
echo "exit=$?"
sleep 2
mount | grep disk0s2
