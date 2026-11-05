# 专题文档索引

按主题记录这台机器（AMD R7 8845H + MT7922 + RTX 4060）逐项打通的结论，每条都有实测支撑。

| 文档 | 内容 |
|---|---|
| [wifi-mt7922.md](wifi-mt7922.md) | MT7922 Wi-Fi 四条路线对比、GTK/CCMP 三层 bug、客户端自动连接改造 |
| [bluetooth-mt7922.md](bluetooth-mt7922.md) | 蓝牙四件套 + `SkipBluetoothAutomaticFirmwareUpdate`，为什么之前一直不上电 |
| [audio-and-mic.md](audio-and-mic.md) | macOS 26 无 AppleHDA、SimpleHDA、NMXAudio 抢占板载 HDA 导致麦克风全零 |
| [apple-id.md](apple-id.md) | `-20970` 五轮误判，真正的解法是清 akd 缓存；iMessage 需人工验证 |
| [camera-uvc.md](camera-uvc.md) | 内置摄像头灯亮零帧的完整排除清单 |
| [gpu-and-display.md](gpu-and-display.md) | NullMoth / BAR13 黑屏 / HiDPI Override / 780M 核显无解 |
| [opencore-and-esp.md](opencore-and-esp.md) | OC 配置要点、ESP 操作与磁盘编号的坑、备份策略 |
| [open-issues.md](open-issues.md) | 仍未解决的问题与可选路线（AirDrop / 相机 / 麦克风） |

## 配套脚本

| 文件 | 作用 |
|---|---|
| [../tools/wifi-autoconnect.sh](../tools/wifi-autoconnect.sh) | MT7922 登录看护：en 口没 IP 且客户端 App 未运行时拉起它 |
| [../tools/ntfs4mac-automount.sh](../tools/ntfs4mac-automount.sh) | NTFS 自动重挂为可写，**所有磁盘操作带硬超时**（旧版无超时会拖死 diskarbitrationd） |

## 一句话结论（写给未来的自己）

1. MT7922 在 macOS 26 只有 `itlmt7922`（Ethernet 后端）能稳定跑，原生菜单那条路会 panic。
2. 蓝牙是 **BlueTool 走了 Broadcom 刷机脚本**，加一个空文件 `/etc/bluetool/SkipBluetoothAutomaticFirmwareUpdate` 就通了。
3. `-20970` 先清 `~/Library/Caches/com.apple.akd`，别急着改三码。
4. `ResizeGpuBars` 永远保持 `-1`，改成 13 必黑屏。
5. 改任何 Wi-Fi / 蓝牙 kext 之后**关机断电 10 秒**，不要热重启。
6. 每次开机磁盘编号都会变，操作 ESP 前先定位，别信上一次的 `disk0s1`。
