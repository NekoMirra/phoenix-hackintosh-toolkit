#!/bin/sh
set -e
W="/Users/mirra/WorkBuddy/2026-11-03-20-03-17/probe/pkg"
SRC="/Users/mirra/WorkBuddy/2026-11-03-20-03-17/probe/AMDProbe.kext"
{
  echo "=== 构建载荷 ==="
  rm -rf "$W"
  mkdir -p "$W/root/Library/Extensions" "$W/scripts"
  cp -R "$SRC" "$W/root/Library/Extensions/"
  chown -R root:wheel "$W/root/Library/Extensions/AMDProbe.kext"
  chmod -R 755 "$W/root/Library/Extensions/AMDProbe.kext"

  cat > "$W/scripts/postinstall" <<'EOS'
#!/bin/sh
codesign -f -s - "/Library/Extensions/AMDProbe.kext" 2>/dev/null
touch /Library/Extensions
exit 0
EOS
  chmod 755 "$W/scripts/postinstall"

  echo "=== pkgbuild ==="
  /usr/bin/pkgbuild --root "$W/root" --scripts "$W/scripts" \
    --identifier com.local.amdprobe --version 1.0 --install-location / \
    "$W/AMDProbe.pkg" 2>&1 | tail -5
  ls -lh "$W/AMDProbe.pkg" | awk '{print $5, $9}'

  echo "=== installer ==="
  /usr/sbin/installer -pkg "$W/AMDProbe.pkg" -target / 2>&1 | tail -8
  echo "installer exit=$?"

  echo "=== 验证 ==="
  ls -ld /Library/Extensions/AMDProbe.kext 2>&1
  ls -l /Library/Extensions/AMDProbe.kext/Contents/MacOS/ 2>&1
} > /Users/mirra/WorkBuddy/2026-11-03-20-03-17/probe/pkg.log 2>&1
chmod 644 /Users/mirra/WorkBuddy/2026-11-03-20-03-17/probe/pkg.log
