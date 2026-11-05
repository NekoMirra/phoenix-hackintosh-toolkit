# 声卡与麦克风：谁在驱动板载 HDA

> codec：Conexant（子系统 `1d05:1407`），控制器 `1022:15e3`（Family 17h/19h HD Audio）

## 背景：macOS 26 没有 AppleHDA.kext 这个文件

`/System/Library/Extensions/AppleHDA.kext` **不存在**（全盘 `find` 无结果），
但符号还在内核集合里：

```
SystemKernelExtensions.kc → AppleHDAController / AppleHDADriver
BootKernelExtensions.kc   → AppleHDA
```

也就是说驱动**在**，只是没有 kext 文件实体，需要别的东西把它「挂」起来。
laobamac 的 **`SimpleHDA.kext`** 就是干这个的：Lilu 插件，内部带 AppleHDA 实现
（4.3MB 二进制，4580 处 AppleHDA 符号），必须和 `AppleALC` 共存，顺序：

```
Lilu → AppleALC → SimpleHDA
```

本机 `layout-id=7` / `alc-layout-id=15`；AppleALC 1.9.9 的 HDAConfigDefault 里
确实含 codec `0x14F11F86` 的 layout 15 / 21，所以 `alcid=15` 是对的。

> `SimpleHDA` 是可选的 HAL 插件（`SimpleHDA-HAL-1.0.0.pkg`），
> 不装走普通 IOAudio 路径也能出声。
> 开关：`-shdaoff`（停声卡）、`-shdahaloff`（停 HAL）。

## 但本机的音频其实是 NullMoth 的 NMXAudio 在驱动

这是查麦克风时才发现的：

```
HDEF@0,6 (1022:15e3)
└── NMXAudio            ← /Library/Extensions/NMXAudio.kext（NullMoth 显卡驱动附带）
kmutil 里没有任何 AppleHDA / AppleHDAController / AppleHDADriver
```

`NMXAudio` 的 personality 是这样写的：

```
IOPCIClassMatch = 0x04030000&0xffff0000     ← 按 PCI 类匹配：任何音频设备通吃
IOProbeScore    = 5000                       ← 远高于 AppleHDA 的 0
```

**它本来只该管显卡的 HDMI 音频（`10de:22be`），却把板载 `HDEF` 一起抢了**，
于是 AppleHDA 永远抢不到，输出能用（NMXAudio 自己实现了 HDA 输出），
输入是空壳：虽然建了 `IOAudioStreamDirection=1` 的引擎，但不接 ADC、不填 DMA buffer。

## 麦克风「有设备、永远静音」的实证

先纠正一个 TCC 常识（我一开始读反了）：`TCC.db` 的 `auth_value` 是
**`0`=拒绝 / `2`=允许**。

用 sqlite 直接给测试程序写授权（SIP 的 Filesystem Protections 已关，可以写用户库），
`killall tccd` 后重测：

```
Conexant (0x1f86) (Right Analog)     输入通道 = 2
Conexant (0x1f86) (Internal Analog)  输入通道 = 2
4 秒采样：峰值 = 0.00000   RMS = 0.00000   样本数 = 192000
```

192000 个样本**全是精确的零**，两个设备、所有数据源都一样 —— 这不是「声音小」，
是驱动根本没往缓冲区里写东西。

> 复现命令：`cd /tmp/mictest2 && ./rec2`（源码见本仓库 journal 对应日期）
> 关键点：命令行程序拿麦克风必须先有 TCC 授权，否则系统会**静默返回全 0**，
> 那种 0 不能当作「麦克风坏」的证据。

## 处理：把 NMXAudio 的匹配收窄

```
IOPCIClassMatch = 0x04030000&0xffff0000
→ IOPCIPrimaryMatch = 0x22be10de        # 只认 NVIDIA 10de:22be（HDMI 音频）
```

这样 `HDEF` 空出来给 AppleHDA + AppleALC + SimpleHDA，HDMI 音频继续由 NMXAudio 负责。
改完 `kmutil install --update-all` 并通过 plist 校验。

**待验证**（写这份文档时尚未重启）：
1. `kmutil showloaded | grep -i AppleHDA` 应出现 AppleHDAController / AppleHDADriver
2. `ioreg -r -n HDEF` 的子节点应是 AppleHDAController，不再是 NMXAudio
3. 重跑采样程序，峰值应 > 0

**回滚**：把备份的 `NMXAudio.kext/Contents/Info.plist` 拷回去再重启。

## 如果 AppleHDA 认不出这颗 codec

那就说明 macOS 26 上这条路也断了，退路依次是：
1. 调 AppleALC layout（15 / 21 / 7 逐个试，改 `alc-layout-id`）
2. `SimpleHDA` 的 HAL 插件 + `shda-lang`
3. 外接 USB 声卡（免驱，最省事）
