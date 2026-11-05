#!/bin/zsh
# 风扇曲线注入 —— 按 open-revo 官方 GCUService 逆向协议
# 表区: CPU UPT 0xF00 / DOWNT 0xF10 / DUTY 0xF20 (16B each)
#       GPU UPT 0xF30 / DOWNT 0xF40 / DUTY 0xF50 (duty 13B)
# 控制字: 0xF5D/0xF5E = max duty, 0xF5F = ctrl (绝不能写 0!)
# 曲线: GAMING 档 (占空比刻度 0-200, step0=0 零转速待机)

EC=./tools/ectool

# ---- Step A: 预脉冲打开闩锁 (0x04 -> 0x00) ----
$EC write 0x7C6 0x04 --i-understand
$EC write 0x7C6 0x00 --i-understand
# ---- Step B: 声明 AP 存在并激活 (0x741 |= 0x81) ----
$EC write 0x741 0x85 --i-understand

# ---- CPU UPT ----
cpu_upt=(00 37 3A 3D 41 45 48 4B 4E 51 FF FF FF FF FF FF)
# ---- CPU DOWNT ----
cpu_downt=(30 3A 3D 41 45 49 4C 4F 52 FF FF FF FF FF FF FF)
# ---- CPU DUTY (step0 必须 0) ----
cpu_duty=(00 3C 46 50 64 6E 78 82 96 A0 A0 A0 A0 A0 A0 A0)

i=0
for a in 0F00 0F01 0F02 0F03 0F04 0F05 0F06 0F07 0F08 0F09 0F0A 0F0B 0F0C 0F0D 0F0E 0F0F; do
  $EC write 0x$a $cpu_upt[$((i+1))] --i-understand >/dev/null || echo "FAIL UPT $a"; i=$((i+1))
done
echo "CPU UPT done"
i=0
for a in 0F10 0F11 0F12 0F13 0F14 0F15 0F16 0F17 0F18 0F19 0F1A 0F1B 0F1C 0F1D 0F1E 0F1F; do
  $EC write 0x$a $cpu_downt[$((i+1))] --i-understand >/dev/null || echo "FAIL DOWNT $a"; i=$((i+1))
done
echo "CPU DOWNT done"
i=0
for a in 0F20 0F21 0F22 0F23 0F24 0F25 0F26 0F27 0F28 0F29 0F2A 0F2B 0F2C 0F2D 0F2E 0F2F; do
  $EC write 0x$a $cpu_duty[$((i+1))] --i-understand >/dev/null || echo "FAIL DUTY $a"; i=$((i+1))
done
echo "CPU DUTY done"

# GPU 表与 CPU 相同
i=0
for a in 0F30 0F31 0F32 0F33 0F34 0F35 0F36 0F37 0F38 0F39 0F3A 0F3B 0F3C 0F3D 0F3E 0F3F; do
  $EC write 0x$a $cpu_upt[$((i+1))] --i-understand >/dev/null || echo "FAIL G-UPT $a"; i=$((i+1))
done
i=0
for a in 0F40 0F41 0F42 0F43 0F44 0F45 0F46 0F47 0F48 0F49 0F4A 0F4B 0F4C 0F4D 0F4E 0F4F; do
  $EC write 0x$a $cpu_downt[$((i+1))] --i-understand >/dev/null || echo "FAIL G-DOWNT $a"; i=$((i+1))
done
i=0
for a in 0F50 0F51 0F52 0F53 0F54 0F55 0F56 0F57 0F58 0F59 0F5A 0F5B 0F5C; do
  $EC write 0x$a $cpu_duty[$((i+1))] --i-understand >/dev/null || echo "FAIL G-DUTY $a"; i=$((i+1))
done
echo "GPU tables done"

# 控制字: max duty 160 (0xA0); 0xF5F 绝不能写 0
$EC write 0x0F5D 0xA0 --i-understand >/dev/null
$EC write 0x0F5E 0xA0 --i-understand >/dev/null
$EC write 0x0F5F 0xA0 --i-understand >/dev/null
echo "ctrl regs done"

# 提交闩锁
$EC write 0x7C6 0x04 --i-understand
echo "latch committed"
