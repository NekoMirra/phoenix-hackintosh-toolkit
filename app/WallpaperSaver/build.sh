#!/bin/sh
# 编译并安装「壁纸同款」屏保，然后把当前壁纸抓成包内资源。
set -e
cd "$(dirname "$0")"

NAME=WallpaperSaver
BUNDLE="$NAME.saver"
OUT="/tmp/$BUNDLE"
DEST="$HOME/Library/Screen Savers/$BUNDLE"

echo "== 1. 编译 =="
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
clang -bundle -fobjc-arc -O2 -target x86_64-apple-macos13.0 \
      -framework ScreenSaver -framework AppKit \
      -o "$OUT/Contents/MacOS/$NAME" WallpaperSaverView.m
cp Info.plist "$OUT/Contents/Info.plist"
echo "   ok"

echo "== 2. 抓当前壁纸 =="
SRC=$(python3 - <<'PY'
import plistlib, os, urllib.parse
p = os.path.expanduser("~/Library/Application Support/com.apple.wallpaper/Store/Index.plist")
try:
    d = plistlib.load(open(p, 'rb'))
    ch = d["AllSpacesAndDisplays"]["Linked"]["Content"]["Choices"][0]
    cfg = plistlib.loads(ch["Configuration"])
    u = cfg["url"]["relative"]
    print(urllib.parse.unquote(u.replace("file://", "")))
except Exception as e:
    print("")
PY
)
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
  echo "   ⚠️ 没读到现在壁纸，保留包里已有图片"
else
  echo "   源文件: $SRC"
  # 缩到 3840 宽 JPEG：屏保全屏用足够，且体积小、加载快
  sips -s format jpeg -s formatOptions 92 -Z 3840 "$SRC" --out "$OUT/Contents/Resources/wallpaper.jpg" >/dev/null 2>&1
  ls -lh "$OUT/Contents/Resources/wallpaper.jpg" | awk '{print "   生成: "$9" "$5}'
fi

echo "== 3. 签名并安装 =="
codesign -f -s - "$OUT" 2>/dev/null || true
mkdir -p "$HOME/Library/Screen Savers"
rm -rf "$DEST"
cp -R "$OUT" "$DEST"
xattr -cr "$DEST" 2>/dev/null || true
echo "   -> $DEST"

echo "== 4. 重启屏保服务 =="
killall ScreenSaverEngine 2>/dev/null || true
killall legacyScreenSaver 2>/dev/null || true
echo "   完成"
