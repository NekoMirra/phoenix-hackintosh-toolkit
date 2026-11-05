#!/bin/sh
# amd-pmsync — 把 macOS 原生电源状态翻译成 AMD SMU 功耗墙
# 状态来源（优先级从高到低）：
#   1. 用户档位文件 ~/Library/Application Support/AMDPowerMode/mode
#      （GUI App 写入；首行 save|balanced|max|custom；custom 时第二行 ppt(mW)、第三行 tctl(℃)）
#   2. 系统超控档 /Library/Preferences/local.amd.powermode（命令行 powermode 写入）
#   3. 电源源为电池                                → 省电墙
#   4. macOS 原生 lowpowermode（当前电源源）        → 省电墙
#   5. 默认                                        → 均衡墙
# 由 /Library/LaunchDaemons/local.amd.pmsync.plist 驱动：
#   开机运行 + 每 60s 轮询 + 监视电源配置/档位文件变化即时触发。

TOOLS="/Users/mirra/WorkBuddy/2026-11-03-20-03-17/tools"
AMDCTL="$TOOLS/amdctl"
USERFILE="/Users/mirra/Library/Application Support/AMDPowerMode/mode"
ROOTOVERRIDE="/Library/Preferences/local.amd.powermode"
STATE="/var/run/local.amd.pmsync.state"
LOG="/var/log/amd-pmsync.log"

[ -x "$AMDCTL" ] || exit 0

# ---- 1. 判定目标模式 ----
mode=""; src_file=""
read_mode() {
    [ -f "$1" ] && head -1 "$1" 2>/dev/null | tr -d '[:space:]'
}
m=$(read_mode "$USERFILE")
case "$m" in save|balanced|max|custom) mode="$m"; src_file="$USERFILE" ;; esac
if [ -z "$mode" ]; then
    m=$(read_mode "$ROOTOVERRIDE")
    case "$m" in save|balanced|max|custom) mode="$m"; src_file="$ROOTOVERRIDE" ;; esac
fi

if [ -z "$mode" ]; then
    # 自动档：先看电源源
    case "$(pmset -g batt 2>/dev/null | head -1)" in
        *Battery*) mode=battery ;;
        *)
            lpm=$(pmset -g 2>/dev/null | awk '/^ *lowpowermode/ {print $2; exit}')
            if [ "$lpm" = "1" ]; then mode=save; else mode=balanced; fi
            ;;
    esac
fi

case "$mode" in
    max)      PPT=54000; TCTL=90 ;;
    balanced) PPT=35000; TCTL=85 ;;
    save)     PPT=15000; TCTL=65 ;;
    battery)  PPT=20000; TCTL=80 ;;
    custom)
        p=$(sed -n '2p' "$src_file" 2>/dev/null | tr -d '[:space:]')
        t=$(sed -n '3p' "$src_file" 2>/dev/null | tr -d '[:space:]')
        case "$p" in ''|*[!0-9]*) p=35000 ;; esac
        case "$t" in ''|*[!0-9]*) t=85 ;; esac
        [ "$p" -lt 8000 ]  && p=8000
        [ "$p" -gt 80000 ] && p=80000
        [ "$t" -lt 60 ]    && t=60
        [ "$t" -gt 100 ]   && t=100
        PPT=$p; TCTL=$t
        ;;
esac

# ---- 2. 风扇强冷（EC 0x751 bit6；档位文件含 "boost" 行则开启）----
ECTOOL="$TOOLS/ectool"
want_boost=0
if grep -q '^boost$' "$USERFILE" 2>/dev/null; then want_boost=1; fi
if [ -x "$ECTOOL" ]; then
    cur=$("$ECTOOL" read 0x751 2>/dev/null | sed -n 's/.*= 0x\([0-9A-Fa-f][0-9A-Fa-f]\).*/\1/p')
    case "$cur" in
        *[0-9A-Fa-f]) cur=$(( 16#$cur )) ;;
        *) cur=0 ;;
    esac
    now_boost=$(( (cur & 0x40) ? 1 : 0 ))
    if [ "$want_boost" != "$now_boost" ]; then
        if [ "$want_boost" = "1" ]; then nb=$(( cur | 0x40 )); else nb=$(( cur & ~0x40 )); fi
        "$ECTOOL" write 0x751 "$(printf '0x%02X' "$nb")" --i-understand >/dev/null 2>&1
        echo "$(date '+%F %T') fanboost=$want_boost 应用成功" >> "$LOG"
    fi
fi

# ---- 3. 状态没变就不动 SMU（避免日志刷屏） ----
sig="$mode/$PPT/$TCTL"
if [ -f "$STATE" ] && [ "$(cat "$STATE" 2>/dev/null)" = "$sig" ]; then
    exit 0
fi

# ---- 3. 下墙 ----
r1=$("$AMDCTL" tctl "$TCTL" 2>&1 | grep -c "0x01")
r2=$("$AMDCTL" ppt "$PPT" 2>&1 | grep -c "0x01")
ok=$((r1 + r2))

if [ "$ok" -eq 4 ]; then
    echo "$(date '+%F %T') mode=$mode ppt=${PPT}mW tctl=${TCTL}℃ 应用成功" >> "$LOG"
    echo "$sig" > "$STATE"
else
    echo "$(date '+%F %T') mode=$mode ppt=${PPT}mW tctl=${TCTL}℃ 部分失败($ok/4)" >> "$LOG"
fi
