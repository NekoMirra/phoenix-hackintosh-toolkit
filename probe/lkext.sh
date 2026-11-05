#!/bin/sh
SRC="/Users/mirra/WorkBuddy/2026-11-03-20-03-17/probe/AMDProbe.kext"
DST="/Library/Extensions/AMDProbe.kext"
{
  echo "=== whoami: $(id -un) ==="
  echo "--- 复制 ---"
  rm -rf "$DST"
  cp -R "$SRC" "$DST" 2>&1
  chown -R root:wheel "$DST"
  chmod -R 755 "$DST"
  ls -ld "$DST" 2>&1
  ls -l "$DST/Contents/MacOS/" 2>&1
  echo "--- 重签名（root 身份）---"
  codesign -f -s - "$DST" 2>&1 | head -3
  codesign -dv "$DST" 2>&1 | grep -E "Identifier|Signature"
  echo "--- 重建内核集合 ---"
  /usr/bin/kmutil install --volume-root / --update-all 2>&1 | grep -v "deprecated" | tail -15
  echo "kmutil exit=$?"
  echo "--- 当前系统里已加载的第三方 kext（参考）---"
  /usr/bin/kmutil showloaded 2>/dev/null | grep -iE "NVRM|NVAccel|HoRNDIS" | head -5
} > /Users/mirra/WorkBuddy/2026-11-03-20-03-17/probe/install.log 2>&1
chmod 644 /Users/mirra/WorkBuddy/2026-11-03-20-03-17/probe/install.log
