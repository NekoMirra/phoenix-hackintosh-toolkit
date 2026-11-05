#!/bin/sh
# 睡眠策略调整：关闭休眠镜像，纯内存睡眠，放宽电池下的等待时间
echo "===== 调整前 ====="
pmset -g custom

echo
echo "===== 应用设置 ====="
pmset -a hibernatemode 0
pmset -a standby 0
pmset -a autopoweroff 0
pmset -b sleep 10
pmset -b displaysleep 5
echo "已写入"

echo
echo "===== 删除休眠镜像 ====="
if [ -f /var/vm/sleepimage ]; then
    rm -f /var/vm/sleepimage && echo "已删除 /var/vm/sleepimage"
else
    echo "无休眠镜像"
fi

echo
echo "===== 调整后 ====="
pmset -g custom
echo
echo "===== 当前生效值 ====="
pmset -g | grep -E "hibernatemode|standby|autopoweroff|^ sleep|displaysleep"
