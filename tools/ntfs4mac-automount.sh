#!/bin/sh
# ntfs4mac-automount — 登录后把被系统只读驱动抢先挂载的 NTFS 卷
# 重新挂载为可读写（走 NTFS4Mac 的 FSKit 扩展）。
# 必须由登录用户运行：FSKit 模块的启用是按用户生效的。
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
LOG="$HOME/Library/Logs/ntfs4mac-automount.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

[ "${1:-}" = "--wait" ] && sleep 10

ro_ntfs() {
    mount | grep '(ntfs' | grep 'read-only' | while IFS= read -r line; do
        dev=${line%% on *}
        rest=${line#* on }
        mnt=${rest%% (ntfs*}
        printf '%s\t%s\n' "$dev" "$mnt"
    done
}

is_rw()      { mount | grep "^$1 " | grep -qv 'read-only'; }
is_mounted() { mount | grep -q "^$1 "; }

flip() {
    dev="$1"; mnt="$2"
    # 先礼后兵：正常卸载失败就用强制卸载。
    # 目标卷此刻必然是只读挂载（没有待写回的缓存），强卸不会丢数据。
    if ! diskutil unmount "$mnt" >>"$LOG" 2>&1; then
        log "  $mnt 被占用，尝试强制卸载（只读挂载，无写入风险）"
        diskutil unmount force "$mnt" >>"$LOG" 2>&1
        sleep 1
        if is_mounted "$dev"; then
            log "  $mnt 强卸失败，跳过（下次登录或手动处理）"
            return 1
        fi
    fi
    sleep 1
    # 挂载 + 最多 3 轮重试：模块首次探测可能仍读到旧判定，
    # 重挂一次通常就翻成读写。
    i=0
    while [ $i -lt 3 ]; do
        diskutil mount "$dev" >>"$LOG" 2>&1
        sleep 2
        if is_mounted "$dev" && is_rw "$dev"; then
            log "  OK $dev -> $mnt 已可读写（第 $((i+1)) 次尝试）"
            return 0
        fi
        i=$((i+1))
        [ $i -lt 3 ] && { log "  第 $i 次仍只读，重挂再试"; diskutil unmount force "$mnt" >>"$LOG" 2>&1; sleep 2; }
    done
    if is_mounted "$dev"; then
        log "  $dev 仍只读：NTFS 日志不干净（Windows 未正常关机/开了快速启动），需先在 Windows 侧清理"
    else
        log "  $dev 挂载失败，已尝试恢复"
        diskutil mount "$dev" >>"$LOG" 2>&1
    fi
    return 1
}

main() {
    mkdir -p "$(dirname "$LOG")"
    log "=== 开机自动挂载开始 ==="
    ro_ntfs | while IFS="$(printf '\t')" read -r dev mnt; do
        [ -n "$dev" ] || continue
        log "检查 $dev ($mnt)"
        flip "$dev" "$mnt"
        # 无论如何保证卷处于挂载状态
        is_mounted "$dev" || { diskutil mount "$dev" >>"$LOG" 2>&1; }
    done
    log "=== 完成 ==="
}

main
