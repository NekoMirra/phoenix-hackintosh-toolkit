#!/bin/sh
# 系统卷 $LogFile 起始 LCN=767653 -> 偏移 767653*4096
dd if=/dev/rdisk0s2 bs=512 skip=$((767653*8)) count=2 2>/dev/null | xxd | head -8
