#!/bin/sh
pmset -c sleep 0        # 接电源时不进入睡眠
pmset -c displaysleep 10
pmset -c powernap 0     # 电源下也关闭 Power Nap，减少意外唤醒
echo "===== 最终配置 ====="
pmset -g custom
echo
echo "===== 休眠镜像 ====="
ls -la /var/vm/ 2>/dev/null | grep -i sleep || echo "无休眠镜像 ✅"
