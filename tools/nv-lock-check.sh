#!/bin/sh
echo "===== install.lock 内容 ====="
ls -la /Library/NullMoth/install.lock/ 2>&1
echo
for f in owner installing restore-incomplete; do
  if [ -e "/Library/NullMoth/install.lock/$f" ]; then
    echo "--- $f ---"
    cat "/Library/NullMoth/install.lock/$f" 2>&1
    echo
  fi
done
echo "===== 当前驱动完整性 ====="
for k in NVRM NVAccel NVRMFB NVRMAGDC; do
  printf "%-9s %s\n" "$k" "$(plutil -extract CFBundleVersion raw /Library/Extensions/$k.kext/Contents/Info.plist 2>/dev/null || echo 缺失)"
done
ls /Library/GPUBundles/ 2>&1
echo
echo "===== 内核集合里的 nullmoth 条目 ====="
kmutil inspect -a x86_64 /Library/KernelCollections/AuxiliaryKernelExtensions.kc 2>/dev/null | grep -o "com\.nullmoth\.[A-Za-z0-9]*" | sort -u
