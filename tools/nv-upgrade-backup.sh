#!/bin/sh
set -u
BK=/Users/mirra/WorkBuddy/2026-11-03-20-03-17/nvdriver/backup-2.6.6
mkdir -p "$BK"

echo "===== 1. 备份现有驱动文件 ====="
for k in NVRM NVAccel NVRMFB NVRMAGDC; do
    if [ -d "/Library/Extensions/$k.kext" ]; then
        ditto "/Library/Extensions/$k.kext" "$BK/$k.kext" && echo "  已备份 $k.kext"
    fi
done
mkdir -p "$BK/GPUBundles"
for b in NVMTLDriver.bundle NVIDIAShared.bundle nvmtl nvmtl-allow.txt; do
    [ -e "/Library/GPUBundles/$b" ] && cp -Rp "/Library/GPUBundles/$b" "$BK/GPUBundles/" && echo "  已备份 GPUBundles/$b"
done

echo
echo "===== 2. 内核集合位置 ====="
ls -la /Library/KernelCollections/ 2>/dev/null | head -5
if [ -f /Library/KernelCollections/AuxiliaryKernelExtensions.kc ]; then
    cp -p /Library/KernelCollections/AuxiliaryKernelExtensions.kc "$BK/AuxiliaryKernelExtensions.kc" \
        && echo "  已备份 AuxiliaryKernelExtensions.kc"
fi

echo
echo "===== 3. 清除陈旧安装锁 ====="
L=/Library/NullMoth/install.lock
if [ -d "$L" ]; then
    ls -la "$L"
    rm -f "$L/owner" "$L/installing" "$L/restore-incomplete"
    rmdir "$L" && echo "  已移除 $L" || echo "  ⚠️ 目录未能移除"
else
    echo "  无锁目录"
fi

echo
echo "===== 4. 备份结果 ====="
du -sh "$BK" 2>/dev/null
find "$BK" -maxdepth 1 -mindepth 1 | sed 's|.*/|  |'
