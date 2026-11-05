#!/bin/sh
# ntfs4mac-automount — 登录后把被系统只读挂载的 NTFS 卷重挂为可读写
# （走 NTFS4Mac 的 FSKit 扩展）。必须由登录用户运行：FSKit 模块按用户生效。
#
# 设计要点：**任何一步都不允许无限阻塞**。
#   - 所有磁盘操作都套 perl alarm 硬超时，超时即 SIGALRM 杀掉该进程；
#   - 杀掉客户端就能释放 diskarbitrationd（实测有效），不会连带卡死全局 diskutil；
#   - 每份卷最多尝试有限次，失败就保持只读，绝不影响系统可用性；
#   - 结束时保证每个卷处于“已挂载”状态（宁只读，不可丢挂载）。
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin

LOG="$HOME/Library/Logs/ntfs4mac-automount.log"
LOCKDIR="$HOME/Library/Logs/.ntfs4mac-automount.lock"

T_UNMOUNT=12        # diskutil unmount 超时
T_UMOUNT=10         # umount（绕过 DiskArbitration）超时
T_FORCE=10          # diskutil unmount force 超时
T_MOUNT=25          # diskutil mount 超时
T_PROBE=8           # diskutil 健康探测超时
SETTLE_MAX=30       # 等待系统完成自身挂载的最长秒数
LOG_MAX=262144      # 日志超过 256KB 时截断

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

# 硬超时执行。perl 先 alarm 再 exec，超时后 SIGALRM 直接终止目标进程。
# 返回 >=128 视为超时（128+SIGALRM(14)=142）。
run_to() {
    _secs=$1; shift
    /usr/bin/perl -e 'alarm shift; exec @ARGV' "$_secs" "$@"
}
timed_out() { [ "${1:-0}" -ge 128 ]; }

rotate_log() {
    [ -f "$LOG" ] || return 0
    _sz=$(/usr/bin/stat -f%z "$LOG" 2>/dev/null || echo 0)
    [ "$_sz" -gt "$LOG_MAX" ] || return 0
    /usr/bin/tail -n 400 "$LOG" >"$LOG.tmp" 2>/dev/null && /bin/mv "$LOG.tmp" "$LOG"
    log "(日志超过上限，已截断)"
}

# 输出：dev<TAB>挂载点<TAB>选项
ntfs_volumes() {
    /sbin/mount 2>/dev/null | /usr/bin/grep ' (ntfs' | while IFS= read -r line; do
        dev=${line%% on *}
        rest=${line#* on }
        mnt=${rest%% (ntfs*}
        opts=${rest#*(}
        opts=${opts%)*}
        printf '%s\t%s\t%s\n' "$dev" "$mnt" "$opts"
    done
}

is_mounted() { /sbin/mount 2>/dev/null | /usr/bin/grep -q "^$1 "; }
is_rw()      { /sbin/mount 2>/dev/null | /usr/bin/grep "^$1 " | /usr/bin/grep -qv 'read-only'; }

# diskutil 是否还活着（能返回就算健康）
da_alive() { run_to "$T_PROBE" /usr/sbin/diskutil list >/dev/null 2>&1; }

# 等系统把卷挂完：连续两次采样数量一致即可，最多 SETTLE_MAX 秒
settle() {
    _i=0; _prev=-1
    while [ "$_i" -lt "$SETTLE_MAX" ]; do
        _n=$(ntfs_volumes | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        [ "$_n" -gt 0 ] && [ "$_n" = "$_prev" ] && return 0
        _prev=$_n
        sleep 2
        _i=$((_i+2))
    done
    return 0
}

# 确保 dev 处于挂载状态；返回 0 表示已挂载
ensure_mounted() {
    dev=$1; mnt=$2
    is_mounted "$dev" && return 0
    log "  重新挂载 $dev"
    run_to "$T_MOUNT" /usr/sbin/diskutil mount "$dev" >>"$LOG" 2>&1
    rc=$?
    if timed_out $rc; then
        log "  !! mount 超时(${T_MOUNT}s)，已终止"
        return 1
    fi
    sleep 1
    is_mounted "$dev" || { log "  !! $dev 未能挂载，需要手工处理"; return 1; }
    return 0
}

# 卸载：先走 diskutil（限时），超时再用 umount 绕过 DiskArbitration
do_unmount() {
    dev=$1; mnt=$2
    run_to "$T_UNMOUNT" /usr/sbin/diskutil unmount "$mnt" >>"$LOG" 2>&1
    rc=$?
    if timed_out $rc; then
        log "  diskutil unmount 超时(${T_UNMOUNT}s)，已强制终止"
        if ! da_alive; then
            log "  !! diskutil 无响应，本轮停止处理后续卷（避免拖死磁盘仲裁）"
            return 2
        fi
    elif [ $rc -eq 0 ] && ! is_mounted "$dev"; then
        return 0
    fi

    is_mounted "$dev" || return 0

    # 方案二：umount 是系统调用，不经过 diskarbitrationd
    log "  改用 umount（绕过 DiskArbitration）"
    run_to "$T_UMOUNT" /sbin/umount "$dev" >>"$LOG" 2>&1
    rc=$?
    if timed_out $rc; then
        log "  umount 也超时(${T_UMOUNT}s)，已终止"
        return 2
    fi
    is_mounted "$dev" || return 0

    # 方案三：强制卸载（只读挂载无写缓存，强卸不丢数据）
    log "  仍在挂载，尝试强制卸载（只读挂载，无写入风险）"
    run_to "$T_FORCE" /usr/sbin/diskutil unmount force "$mnt" >>"$LOG" 2>&1
    rc=$?
    if timed_out $rc; then
        log "  强制卸载超时，已终止"
        return 2
    fi
    sleep 1
    is_mounted "$dev" && { log "  $mnt 被占用，跳过（保持只读）"; return 1; }
    return 0
}

flip() {
    dev=$1; mnt=$2
    if is_rw "$dev"; then
        log "  $mnt 已是可读写，跳过"
        return 0
    fi

    do_unmount "$dev" "$mnt"; rc=$?
    [ $rc -eq 2 ] && return 2            # 磁盘服务异常，中止整轮

    if is_mounted "$dev"; then          # 卸不掉就不折腾，保证还在
        ensure_mounted "$dev" "$mnt"
        return 1
    fi

    sleep 1
    i=1
    while [ $i -le 2 ]; do
        run_to "$T_MOUNT" /usr/sbin/diskutil mount "$dev" >>"$LOG" 2>&1
        rc=$?
        if timed_out $rc; then
            log "  mount 超时(${T_MOUNT}s)，已终止"
            break
        fi
        sleep 2
        if is_mounted "$dev" && is_rw "$dev"; then
            log "  OK $dev -> $mnt 已可读写（第 $i 次尝试）"
            return 0
        fi
        log "  第 $i 次仍只读"
        [ $i -lt 2 ] && {
            run_to "$T_FORCE" /usr/sbin/diskutil unmount force "$mnt" >>"$LOG" 2>&1
            [ $? -ge 128 ] && { log "  强卸超时，停止重试"; break; }
            sleep 1
        }
        i=$((i+1))
    done

    ensure_mounted "$dev" "$mnt"
    is_mounted "$dev" && log "  $dev 保持只读：可能 NTFS 日志不干净（Windows 未正常关机 / 开了快速启动）"
    return 1
}

main() {
    /bin/mkdir -p "$(/usr/bin/dirname "$LOG")"
    rotate_log

    # 单实例：上一个实例还卡着的话，绝不再起一个
    if ! /bin/mkdir "$LOCKDIR" 2>/dev/null; then
        log "已有实例在运行，本次跳过"
        return 0
    fi
    trap '/bin/rmdir "$LOCKDIR" 2>/dev/null' EXIT INT TERM HUP

    [ "${1:-}" = "--wait" ] && settle

    log "=== 开机自动挂载开始 ==="

    if ! da_alive; then
        log "diskutil 当前无响应，全部跳过（保持只读，不影响系统）"
        log "=== 结束（跳过） ==="
        return 0
    fi

    TMP="$HOME/Library/Logs/.ntfs4mac-vols.$$"
    ntfs_volumes >"$TMP" 2>/dev/null
    if [ ! -s "$TMP" ]; then
        /bin/rm -f "$TMP"
        log "没有 NTFS 卷需要处理"
        log "=== 完成 ==="
        return 0
    fi

    while IFS="$(printf '\t')" read -r dev mnt opts; do
        [ -n "${dev:-}" ] || continue
        log "检查 $dev ($mnt)"
        flip "$dev" "$mnt"; rc=$?
        if [ $rc -eq 2 ]; then
            log "磁盘服务异常，中止本轮（剩余卷保持只读）"
            break
        fi
        # 无论成败，保证卷是挂载着的
        ensure_mounted "$dev" "$mnt" >/dev/null 2>&1
    done <"$TMP"

    /bin/rm -f "$TMP"
    log "=== 完成 ==="
}

main "$@"
