#!/bin/sh
# 用 /etc/fstab + UUID 强制挂载选项，测哪种 fs 名能真正传给 ntfs4mac 模块
set -u
UUID="$1"
DEV="$2"
MP="$3"

show() {
    mount | grep "^$DEV " || echo "(未挂载)"
}

try_type() {
    t="$1"
    echo "--- 尝试 fstab 类型: $t ---"
    printf 'UUID=%s none %s rw,noatime,remove_hiberfile 0 0\n' "$UUID" "$t" > /etc/fstab
    cat /etc/fstab
    diskutil unmount "$MP" >/dev/null 2>&1
    sleep 1
    diskutil mount "$DEV" 2>&1
    sleep 2
    show
}

echo "== 备份原 fstab（若有）=="
[ -f /etc/fstab.bak ] || cp /etc/fstab /etc/fstab.bak 2>/dev/null

try_type ntfs
case "$(mount | grep "^$DEV ")" in
    *read-only*) echo "!! ntfs 类型仍只读，换 ntfs4mac"; try_type ntfs4mac ;;
    *) echo "== OK =="; exit 0 ;;
esac

case "$(mount | grep "^$DEV ")" in
    *read-only*|"") echo "!! ntfs4mac 也没成功"; rm -f /etc/fstab; diskutil mount "$DEV" >/dev/null 2>&1 ;;
    *) echo "== OK ==" ;;
esac
show
