# 未解决问题与可选路线

更新时间：2026-11-05

## 1. AirDrop / 接力 / 通用剪贴板 —— 缺 AWDL

**现状：完全不可用。** 这不是配置问题：

```sh
ifconfig -l                        # 没有 awdl0
ioreg -c IO80211Interface | wc -l  # 0
system_profiler SPAirPortDataType  # 只有软件版本，没有 Interfaces 段
```

`itlmt7922` 把 MT7922 暴露成一块**以太网卡**（en2），系统里根本没有 AirPort 接口，
`awdl0` 自然不存在。而 AirDrop、Handoff、通用剪贴板、iPhone 蜂窝通话、连续互通相机、
Sidecar、AirPlay 接收**全部依赖 AWDL**。

蓝牙修好不等于 AirDrop 能用 —— 这是两个方向的事（macOS 也早已移除 OBEX 蓝牙传文件）。

### 三条可选路线

| 路线 | 能拿到 | 代价 / 风险 |
|---|---|---|
| **A. `AirportMtkWlan` 1.5.0** | 原生 Wi-Fi 菜单、钥匙串、自动加入 | **AWDL 仍为 ❌**（作者状态表明确写 `AirDrop / Handoff / Continuity (AWDL) ❌`）；5GHz 只有 legacy 20MHz；需要 `DisableIoMapper=true`。1.7.0 在本机 100% panic |
| **B. Apple `AppleSunriseWLAN.dext` + MT7922 固件** | **唯一有 AWDL 希望的路线** | 需要改签名系统卷、关 authenticated-root、bless 新快照，每次系统更新重做；社区目前死在「无线电不扫描」 |
| **C. 换 Broadcom `BCM94360NG`（M.2 2230）** | 原生 AirPort + AWDL，AirDrop/接力/相机/Sidecar 全通 | 要拆机；MT7922 拆下后本仓库这套 Wi-Fi 修复就用不上了（原生卡走系统栈，反而省心） |

### 路线 B 的证据（为什么值得等）

本机 `macOS 26.7.2` 自带的 `com.apple.AppleSunriseWLAN.dext`：

```
IOPCIMatch = 0x792214c3 0x792314c3 0x793214c3      ← 我们的 14c3:7922 就在里面
personality: DriverKit_IO80211AWDL / DriverKit_IO80211AWDLLLW
二进制里: Sources/AppleSunriseWLAN_driverkit/MTK/chips/mt7922/mt7922.c
         以及 (AWDL INFO/ERROR) 日志串、SoftAPConcurrencyEnabled: infra=.. awdl=.. softAp=..
```

也就是说**苹果自己的驱动既支持这颗芯片、也带 AWDL 通道**。
它现在不工作的原因只是 `dext` 目录里放的是 MT7932 的固件（`IZUBA_*`）。

社区（tonymacx86，Elias64Fr / CaseySJ）的做法：
把 `WIFI_MT7922_patch_mcu_1_1_hdr.bin` + `WIFI_RAM_CODE_MT7922_1.bin`（改名 `W7922_1.bin`）
+ `wifi.cfg` 塞进 dext，加 boot-args：

```
ioimageloader.debug.csr-access=1
mtk.wlan.manufacture=1
mtk.wlan.platform=izuba    # 或 pinecrest / katsura / whitepine / codia
```

已验证的进度：固件加载成功、设备树完整、Wi-Fi 图标出现（没打叉），
**但扫描不到任何 SSID**（"Something seems to lock radio activation and network scanning"）。
截至写这份文档仍未解决。

## 2. 麦克风 —— 已定位，待验证

见 [audio-and-mic.md](audio-and-mic.md)：NullMoth 的 `NMXAudio` 按 PCI 类抢走了板载 `HDEF`，
导致 AppleHDA 不加载，输入引擎是空壳（实测 4 秒 192000 样本全 0）。
已把 NMXAudio 的匹配收窄到 `10de:22be`，**待重启验证**。

## 3. 内置摄像头 —— 判定为栈不兼容

见 [camera-uvc.md](camera-uvc.md)。硬件好的（Windows 正常），
PROBE/COMMIT 正常、pipe 建好，但 `packetsReceived=0`，连控制端点都挂住。
可选：外接 UVC 摄像头，或直接用 Windows。

## 4. iMessage / FaceTime —— 等 Apple 客服

苹果明确要求人工验证（顾客代码在 `identityservicesd.plist` 的 `Registration.AlertInfo` 里）。
见 [apple-id.md](apple-id.md)。账号是新注册的，新号被风控拦属常见现象。

## 5. 核显 780M —— 无解

RDNA3 没有任何可用驱动，见 [gpu-and-display.md](gpu-and-display.md)。

## 6. 蓝牙的能力边界

`Chipset: THIRD_PARTY_DONGLE` 是正常结果（基础蓝牙栈）：
A2DP 音频、HID 键鼠、AirPods 音频、BLE 外设都能用；
走 Apple 连续互通的那部分（自动切换、接力）需要 AWDL，同上不可用。

## 7. NTFS 只读的老问题

不是脚本的问题，是 Windows **快速启动**留下的 `hibernated=true` 标志：

```
probe disk0s2: NTFS "系统"  dirty=true hibernated=true    ← 拒绝可写
probe disk3s1: NTFS "Ventoy" dirty=true hibernated=false  ← 允许可写
```

Windows 侧 `powercfg -h off`（或关机时按 Shift）之后即可自动变可写。
**不要**用 `remove_hiberfile` 之类强删，会丢 Windows 会话状态。
