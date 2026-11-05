#!/bin/sh
L=/Library/NullMoth/install.lock
echo "== 锁目录完整内容 =="
ls -la "$L" 2>&1
echo
echo "== 递归 =="
find "$L" 2>&1
