#!/bin/sh
echo "== 文件属性 =="; ls -lO /etc/fstab; echo "内容:"; cat /etc/fstab
echo "== 尝试清空 =="
: > /etc/fstab; echo "truncate exit=$?"
cat /etc/fstab; ls -la /etc/fstab
echo "== 尝试移动到临时目录 =="
/bin/mv /etc/fstab /tmp/fstab.bad.$$ 2>&1; echo "mv exit=$?"
ls -la /etc/fstab 2>&1
