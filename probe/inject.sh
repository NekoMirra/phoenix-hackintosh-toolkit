#!/bin/sh
set -e
SRC="/Users/mirra/WorkBuddy/2026-11-03-20-03-17/probe/AMDProbe.kext"
EFI="/tmp/efimnt"
MNTLOG="/Users/mirra/WorkBuddy/2026-11-03-20-03-17/probe/inject.log"
{
  echo "=== 挂载 ESP ==="
  mkdir -p "$EFI"
  /usr/sbin/diskutil mount -mountPoint "$EFI" disk0s1 2>&1 | head -2
  sleep 1
  if [ ! -d "$EFI/EFI/OC" ]; then echo "EFI 未挂载，中止"; exit 1; fi
  OC="$EFI/EFI/OC"

  echo "=== 备份 config.plist ==="
  cp "$OC/config.plist" "$OC/config.plist.bak-amdprobe"
  ls -l "$OC/config.plist.bak-amdprobe" | awk '{print $5, $9}'

  echo "=== 复制 kext ==="
  rm -rf "$OC/Kexts/AMDProbe.kext"
  cp -R "$SRC" "$OC/Kexts/"
  chown -R root:wheel "$OC/Kexts/AMDProbe.kext"
  chmod -R 755 "$OC/Kexts/AMDProbe.kext"
  ls -l "$OC/Kexts/AMDProbe.kext/Contents/MacOS/AMDProbe" | awk '{print $5, $9}'

  echo "=== 磁盘剩余 ==="
  df -h "$EFI" | tail -1

  echo "=== 写入 Kernel->Add ==="
  /usr/bin/python3 - <<'PY'
import plistlib
P = "/tmp/efimnt/EFI/OC/config.plist"
d = plistlib.load(open(P, "rb"))
add = d["Kernel"]["Add"]
names = [e.get("BundlePath", "") for e in add]
if "AMDProbe.kext" in names:
    print("已存在，跳过")
else:
    e = {
        "Arch": "x86_64",
        "BundlePath": "AMDProbe.kext",
        "Comment": "AMDProbe - SMN/SMU channel (custom build)",
        "Enabled": True,
        "ExecutablePath": "Contents/MacOS/AMDProbe",
        "MaxKernel": "",
        "MinKernel": "",
        "PlistPath": "Contents/Info.plist",
    }
    idx = names.index("VirtualSMC.kext") + 1 if "VirtualSMC.kext" in names else len(add)
    add.insert(idx, e)
    plistlib.dump(d, open(P, "wb"))
    print("已插入到第", idx, "位")
print("--- 加载顺序 ---")
for i, x in enumerate(add):
    mark = "*" if "AMD" in x.get("BundlePath", "") else " "
    print(" ", i, mark, x.get("BundlePath"), "enabled=", x.get("Enabled"))
PY

  echo "=== 校验 ==="
  /usr/bin/plutil -lint "$OC/config.plist"
  echo "=== 卸载 ESP ==="
  /usr/sbin/diskutil unmount "$EFI" 2>&1 | head -2
  echo DONE
} > "$MNTLOG" 2>&1
chmod 644 "$MNTLOG"
