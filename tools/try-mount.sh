#!/bin/sh
echo "== 挂载 系统 =="
diskutil mount /dev/disk0s2 2>&1
echo "exit=$?"
sleep 3
echo "== 挂载表 =="
mount | grep disk0s2 || echo "(未挂载)"
echo "== 模块日志 =="
log show --last 60s --info --predicate 'process == "NTFSExtension" OR process == "fskitd"' 2>&1 | grep -viE "libxpc|BoardServices|lifs_" | grep -iE "disk0s2|refus|error|fail|activat|read-write|read-only" | tail -12
