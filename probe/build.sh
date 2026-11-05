#!/bin/sh
# 编译 AMDProbe.kext（无需完整 Xcode，只用 Command Line Tools）
set -e
cd "$(dirname "$0")"
SDK="$(xcrun --show-sdk-path)"
KH="$SDK/System/Library/Frameworks/Kernel.framework/Headers"

xcrun clang++ -isysroot "$SDK" -I"$KH" \
  -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT \
  -fno-builtin -fno-common -fapple-kext -mkernel -std=c++17 \
  -fno-rtti -fno-exceptions -fno-stack-protector -O2 \
  -Wno-inconsistent-missing-override \
  -c AMDProbe.cpp -o AMDProbe.o 2>&1 | grep -E "error" || true
test -f AMDProbe.o

rm -f AMDProbe.kext/Contents/MacOS/AMDProbe
xcrun clang++ -isysroot "$SDK" -nostdlib -fapple-kext -Xlinker -kext \
  -L"$SDK/usr/lib" -lkmod -lkmodc++ -lcc_kext \
  -o AMDProbe.kext/Contents/MacOS/AMDProbe AMDProbe.o kmod_info.o 2>&1 \
  | grep -v "newer 'macOS'" || true

codesign -f -s - AMDProbe.kext 2>/dev/null
echo "构建完成: $(ls -l AMDProbe.kext/Contents/MacOS/AMDProbe | awk '{print $5}') bytes"
