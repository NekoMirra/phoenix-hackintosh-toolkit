#!/bin/sh
echo "== /var/db 中含 ntfs4mac 的文件 =="
grep -rl "ntfs4mac" /var/db /Library/Application\ Support 2>/dev/null | head -20
echo "== 含 enabledModules 的库 =="
find /var/db /Library -maxdepth 3 -iname "*moduleenable*" -o -maxdepth 3 -iname "*fskit*" 2>/dev/null | head -20
echo "== ModuleEnablement 扩展容器 =="
ls -la /Users/mirra/Library/Containers/com.apple.fskit.ModuleEnablement/Data/Library/Preferences/ 2>/dev/null
echo "== 该容器 Preferences 内容 =="
for f in /Users/mirra/Library/Containers/com.apple.fskit.ModuleEnablement/Data/Library/Preferences/*.plist; do echo "--$f"; plutil -p "$f" 2>/dev/null | head -20; done
