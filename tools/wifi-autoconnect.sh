#!/bin/sh
# MT7922 (ItlWiFi7922) Wi-Fi 自动连接看护
# en2 没有 IPv4 且 App 未运行时，拉起 App 让它在启动时自动重连已保存的网络

APP_ID="local.experimental.ItlWiFi7922.enterprise-test1"
APP_PATH="/Applications/ItlWiFi7922企业测试版_副本.app"
IF="en2"
LOG="$HOME/Library/Logs/wifi-autoconnect.log"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

# 已有 IPv4：说明连上了，直接退出
if /sbin/ifconfig "$IF" 2>/dev/null | /usr/bin/grep -q 'inet '; then
    exit 0
fi

# App 已经在跑：多半正在连接，交给它自己
if /usr/bin/pgrep -f "ItlWiFi7922" >/dev/null 2>&1; then
    log "en2 没有 IPv4，App 正在运行，等待其自动重连"
    exit 0
fi

log "en2 没有 IPv4 且 App 未运行 -> 拉起 App"
/usr/bin/open -b "$APP_ID" 2>>"$LOG" || /usr/bin/open -a "$APP_PATH" 2>>"$LOG"
