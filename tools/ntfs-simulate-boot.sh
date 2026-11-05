#!/bin/sh
echo "== 以 root 身份重挂载 disk3s1（模拟开机时系统驱动抢先挂载）=="
diskutil unmount force /Volumes/Ventoy >/dev/null 2>&1
sleep 1
diskutil mount /dev/disk3s1 2>&1
sleep 2
mount | grep disk3s1
