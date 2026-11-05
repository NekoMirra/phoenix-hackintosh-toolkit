# 机械革命无界 14 · Ryzen 7 8845H 黑苹果调优笔记

> macOS 26.7.2 (25G332) / AMD Ryzen 7 8845H (Phoenix, family 0x19) / RTX 4060 Laptop
> 外接 2560×1600@240Hz，内屏 2560×1600@240Hz
  
这台机器跑起来的难点不在「装上」，而在装完之后：AMD 移动端没有可用的 P-State 调频、
风扇没有 SMC 传感器、NTFS 只读、NVIDIA 靠第三方驱动。这个仓库是把它逐项打通的全过程，
包含自研工具、可复现的验证方法，以及每一个踩过的坑。

## 成果一览

| 目标 | 手段 | 状态 |
|---|---|---|
| CPU 功耗/温度墙 | 自研 `AMDProbe.kext` 直通 Phoenix SMU 邮箱（PPT-fast/slow、Tctl、STAPM） | ✅ |
| 四档功耗模式的系统联动 | `amd-pmsync.sh` + launchd，跟随 macOS 原生低电量/电池状态 | ✅ |
| 菜单栏控制 | 自写 SwiftUI `AMDPowerMode.app`，实时温度 + 档位 + 风扇强冷 | ✅ |
| 风扇控制 | 自研 kext 打通同方 EC（`\_SB.INOU` ECRR/ECRW），找到唯一生效位 0x751 bit6 | ✅ 两态（自动曲线 / 强冷） |
| NTFS 读写 | 定位 FSKit「$LogFile 不干净」闸门，登录后自动重挂 | ⚠️ 见下文限制 |
| 开机亮度恢复 | 自维护状态文件 + 常驻守护写回（驱动 NVRAM 与 macOS 都不持久化） | ✅ |
| Win+L 锁屏 | Karabiner complex_modifications + 自研 `locknow` | ✅ |
| NVIDIA 硬解硬编 | NullMoth 2.7.1 实测：H.264/HEVC 解码 ✅，编码 ❌（Ada 未实现） | ✅ 已测明 |

## 目录结构

```
probe/      自研 AMDProbe.kext 源码（SMU 邮箱 + ACPI EC 通道）
tools/      用户态工具与脚本（全部附源码）
app/        AMDPowerMode 菜单栏 App（SwiftUI 单文件）
docs/       按主题整理的结论 + journal/ 逐日工作记录
```

## 关键结论（每一条都有实测支撑）

### 1. AMD 移动端改 P-State 是死路

`AMDRyzenCPUPowerManagement` 的 selector 11/12/13/15 全部试过，`limit P2`、关 CPB 对频率
零影响；Zen4 移动端走 CPPC 自主调频，`PStateDef`/`PStateCtl` 这类 MSR 在 Phoenix 上不生效。
**唯一有效路径是 SMU 邮箱**（RyzenAdj 同一机制）：
msg `0x3B10528` / rep `0x3B10578` / arg `0x3B10998`，SMN 走 PCI 配置空间 `0xB8`(索引)/`0xBC`(数据)。

### 2. 温度要看 EC，不要看 SMC

SMC 的 `TC0P` 是黑苹果 emulation 的假读数，与真实值差 25–40℃。
真实 CPU 温度在 EC 的 `0x701`（`0x703` 同步），`0x704` 恒 68 是坏传感器。

### 3. 风扇只有两态，静音只能靠压功耗

`0x740` 是 PROJECT_ID（误写成风扇 duty 会把机型 ID 改掉，本人踩过）；
`0x75B/0x75C` 是实时占空比镜像（只读）；`0xF00–0xF5F` 的 RAM 风扇曲线表在本机 EC 固件里
写入即被清空。**唯一生效开关是 `0x751` bit6**（`0x40`）→ 占空比 100%。
ROM 曲线严格跟随 `0x701`：≤65℃ 地板 2000rpm，94℃ 才 2600–3130rpm。
所以「安静」= 把功耗墙压到 15W / 65℃（实测 2034rpm，比均衡档低 35%）。

### 4. NTFS 只读的真正闸门

不是 `$Volume` 脏标志（实测 flags=0x0000），而是 `ntfs_is_logfile_clean` 判定需要回放
`$LogFile`，FSKit 模块对这种卷直接拒绝 rw 且不自动 replay。macOS 侧三条路全部无效：
`fsck_fskit -y` 只核查、`diskutil -mountOptions` 不透传、`/etc/fstab` 同样不透传。
**唯一解**是回 Windows 正常关机（或 `powercfg /h off`）让日志回放，之后登录脚本即可自动挂成读写。

### 5. 开机亮度：两边都没存，连驱动的 NVRAM 变量也不能信

- 驱动 `NVRMFB` 有 NVRAM 变量 `nullmoth-backlight`，但只写不读，没有恢复路径；
- macOS 侧 `/var/root/.../com.apple.CoreBrightness.plist` 里没有这块屏的 `DisplayPreferences`。

变量编码（实测）：`[0x02][u16 小端 = 亮度×65535]`。但它**不能当持久化来源**，两个原因都实测过：
1. 开机时驱动会把 100% 写回去，覆盖上一次会话的值（开机 70 秒后读到的就是 65535）；
2. 写入是延迟/去抖的，实测滞后几十秒到几分钟（屏幕已在 0.596，变量还停在 0.475）。

另外实测：显示器休眠/唤醒**不会**重置亮度（`pmset displaysleepnow` + `caffeinate -u` 前后一致），
所以只需要防开机那一次覆盖。

`tools/brightness-daemon.sh` 因此自己维护 `~/.local/state/brightness-target`：
启动后连写 8 次压住 WindowServer 的默认推送，60 秒保护期内偏离即写回，之后把偏离当作用户改动记录下来。
`tools/brightness.c` 提供唯一可靠的读写通道（DisplayServices 私有 API），`-q` 供守护轮询。

### 6. 硬解判定不能用 VTIsHardwareDecodeSupported

该 API 对 H.264 报 false 是假阴性。正确姿势是用
`VTDecompressionSession` + `kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder`
实测能否建会话。实测 H.264/HEVC 解码均可硬件，编码均不可（Ada 未实现 NVENC）。

## 工具用法

```sh
# 功耗档位（battery / save / balanced / max / auto）
cd tools && ./powermode save status

# SMU 直读直写
./amdctl info
./amdctl ppt 15000 65000      # STAPM/PPT-fast 15W, PPT-slow 65W
./amdctl tctl 65

# EC 读写（写操作有 32 次配额，需先 arm）
./ectool info
./ectool read 0x701           # 真实 CPU 温度
./ectool dump ec.bin 0xF00 0xF5F

# 亮度
./brightness                  # 打印当前
./brightness 0.4              # 设为 40%
```

## 已知限制

- 睡眠：`hibernatemode=0`、`standby=0`，`/var/vm/sleepimage` 随之删除（省 1GB）。
- 蓝牙/无线（MT7922）与显示器刷新率未在本次范围内处理。
- Apple 智能在本机**硬件层面不可用**：无 ANE，`/System/Library/AssetsV2` 下没有任何
  Foundation Model 资产下发；网络上的 enableAppleAI 一类工具明确要求 M1+，不适用。
- 所有 kext 改动都必须走 OpenCore EFI 注入，boot KC 成员无法热替换。

## 网络 / 影音 / iCloud（2026-11-04 ~ 11-05）

这一轮把「装完之后连不上网、没有声音、登不上账号」的部分全部走了一遍，
结论都落在 `docs/` 下的 8 篇专题里（索引见 [docs/README.md](docs/README.md)）。

| 目标 | 手段 | 状态 |
|---|---|---|
| MT7922 Wi-Fi 可用 | `itlmt7922`（Ethernet 后端）+ 自写 CCMP 组播解密 + 信道表 / 看门狗补丁 | ✅ 含校园网强制门户 |
| Wi-Fi 开机自动连 | 改 `ItlWiFi7922` 源码（启动扫描 + 记住上次 SSID）+ 登录看护脚本 | ✅ |
| MT7922 蓝牙 | `SimpleMtkBtFw` + `SimpleMtkBtPatcher` + `MtkBtIdMask` + `BlueToolFixup` + `SkipBluetoothAutomaticFirmwareUpdate` | ✅ 必须冷启动 |
| 内置麦克风 | 定位到 NullMoth `NMXAudio` 按 PCI 类抢占板载 HDA，输入引擎是空壳 | ⚠️ 待重启验证 |
| Apple ID / iCloud | 配套三码 + 清 `akd` 认证缓存 | ✅ |
| iMessage / FaceTime | 苹果要求人工验证（新号风控），与配置无关 | ⛔ 需联系客服 |
| 内置摄像头 | UVC isoch 收不到包；权限/带宽/端口/驱动均已排除 | ❌ 无解 |
| AirDrop / 接力 | MT7922 无 AWDL，只能换 Broadcom 卡或等 Apple SunriseWLAN | ❌ |
| 独显 BAR 优化 | `ResizeGpuBars=13` → 四个显示头全灭、黑屏 | ❌ 已回滚 |

另外 `tools/ntfs4mac-automount.sh` 被重写了：旧版**没有任何超时**，一次卡住就会把
`diskarbitrationd` 拖死，之后所有 `diskutil` 命令（连 `diskutil list`）无限挂起、ESP 也挂不上。
新版每个磁盘操作都套 `perl alarm` 硬超时、三级降级卸载、单实例锁，卡住时宁可保持只读也不拖死系统。

## 免责

全部操作针对本人这一台机器，EC 寄存器与 SMU 消息 ID 换机型即不适用。
盲目写 EC 可能改坏机型 ID 或触发风扇看门狗，**写之前先只读确认**。
