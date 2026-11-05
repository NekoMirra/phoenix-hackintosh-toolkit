#!/bin/bash
# brightness-daemon.sh — 记住并恢复内屏亮度
#
# 为什么不能只靠 NVRMFB 的 NVRAM 变量 nullmoth-backlight：
#   1) 驱动开机不会读它，反而会被开机时的 100% 覆盖掉（实测开机 70 秒后变量已是 65535）；
#   2) 驱动的写入是延迟/去抖的，实测会滞后几十秒到几分钟。
# 所以自己维护一份状态文件，开机后由本进程写回，之后持续跟踪用户改动。
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin

BIN="$HOME/.local/bin/brightness"
STATE="$HOME/.local/state/brightness-target"
LOG="$HOME/Library/Logs/brightness-daemon.log"
TICK=${TICK:-2}          # 轮询间隔（秒）
TOL=0.006       # 变化判定阈值
GRACE=${GRACE:-60}       # 启动后这段时间内，把偏离视为系统推送并盖回去

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

mkdir -p "$(dirname "$STATE")" 2>/dev/null
[ -f "$LOG" ] && [ "$(stat -f%z "$LOG" 2>/dev/null || echo 0)" -gt 262144 ] && tail -n 300 "$LOG" >"$LOG.tmp" 2>/dev/null && /bin/mv "$LOG.tmp" "$LOG"

save() {
    printf '%s\n' "$1" >"$STATE.tmp" 2>/dev/null && /bin/mv "$STATE.tmp" "$STATE" 2>/dev/null
}

NUM='^[01]\.[0-9]+$|^1\.0+$|^0$'
target=""
if [ -f "$STATE" ]; then
    target=$(head -1 "$STATE" 2>/dev/null | tr -d ' \n')
fi
if ! printf '%s' "${target:-}" | grep -Eq "$NUM"; then
    target=$("$BIN" -q 2>/dev/null)
    printf '%s' "${target:-}" | grep -Eq "$NUM" || exit 0
    save "$target"
    log "初始化状态文件：$target"
fi

START=$(date +%s)

# 开机阶段：系统会把背光推到 100%，连续盖回去
for ((i=0; i<${WARM:-8}; i++)); do
    "$BIN" "$target" >/dev/null 2>&1
    sleep 3
done
log "启动完成，目标 $target"

while :; do
    sleep $TICK
    cur=$("$BIN" -q 2>/dev/null)
    printf '%s' "${cur:-}" | grep -Eq "$NUM" || continue

    # 判定偏差是否超过阈值
    if awk -v a="$cur" -v b="$target" -v t="$TOL" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d>t)}'; then
        elapsed=$(( $(date +%s) - START ))
        if [ "$elapsed" -lt "$GRACE" ]; then
            "$BIN" "$target" >/dev/null 2>&1
            log "开机保护期内被改成 $cur，写回 $target"
        else
            target="$cur"
            save "$target"
            log "记录用户改动：$target"
        fi
    fi
done
