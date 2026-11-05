#!/bin/sh
echo "===== 本次开机 backlight 日志 ====="
log show --last 20m --predicate 'eventMessage CONTAINS[c] "backlight" OR eventMessage CONTAINS[c] "brightness"' 2>/dev/null | grep -iE "backlight|brightness" | tail -30
