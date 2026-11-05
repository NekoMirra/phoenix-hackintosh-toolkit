#!/bin/sh
L=/Library/NullMoth/install.lock
if [ -d "$L" ]; then
    echo "== 清除陈旧锁 =="
    rm -f "$L/owner" "$L/installing" "$L/restore-incomplete"
    rmdir "$L" 2>/dev/null && echo "锁已移除" || echo "锁目录未能移除"
fi
cd /Users/mirra/WorkBuddy/2026-11-03-20-03-17/nvdriver/pkgroot || exit 1
echo "== 开始安装 2.7.1 =="
./install.sh
rc=$?
echo "== install.sh 退出码: $rc =="
echo "== 安装后版本 =="
for k in NVRM NVAccel NVRMFB NVRMAGDC; do
    printf "%-9s %s\n" "$k" "$(plutil -extract CFBundleVersion raw /Library/Extensions/$k.kext/Contents/Info.plist 2>/dev/null || echo 缺失)"
done
echo "== NullMoth 记录版本 =="
cat /Library/NullMoth/driver-version 2>/dev/null
