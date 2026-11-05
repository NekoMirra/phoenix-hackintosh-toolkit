#!/bin/sh
echo "== 谁在占用 数据 卷 =="
lsof 2>/dev/null | grep "/Volumes/数据" | awk '{print $1, $2, $9}' | sort -u | head -15
echo "== mds 索引进程 =="
ps aux | grep -E "[m]ds|mdworker" | awk '{print $2, $11, $12}' | head -8
