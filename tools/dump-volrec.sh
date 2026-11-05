#!/bin/sh
# 系统卷: MFT 偏移 3221225472 + 3*1024
OFF=$((3221225472 + 3072))
echo "记录偏移: $OFF"
dd if=/dev/rdisk0s2 bs=512 skip=$((OFF/512)) count=2 2>/dev/null | xxd | head -32
