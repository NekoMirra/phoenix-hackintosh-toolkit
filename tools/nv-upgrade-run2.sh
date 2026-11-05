#!/bin/sh
L=/Library/NullMoth/install.lock
STAMP=$(date +%Y%m%d-%H%M%S)
if [ -d "$L" ]; then
    echo "== 把陈旧锁挪走 =="
    /bin/mv "$L" "/Library/NullMoth/stale-install.lock.$STAMP" && echo "已挪到 /Library/NullMoth/stale-install.lock.$STAMP"
fi
ls -la /Library/NullMoth/ | head -12

LOG=/Users/mirra/WorkBuddy/2026-11-03-20-03-17/nvdriver/install-2.7.1.log
cd /Users/mirra/WorkBuddy/2026-11-03-20-03-17/nvdriver/pkgroot || exit 1
echo "== 开始安装 =="
./install.sh > "$LOG" 2>&1
rc=$?
echo "== 退出码: $rc =="
echo "== 日志尾部 =="
tail -30 "$LOG"
