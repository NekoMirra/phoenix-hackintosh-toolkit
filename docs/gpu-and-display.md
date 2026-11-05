# 独显与显示：BAR 千万别动

> RTX 4060 Laptop（`10de:28a0` + 音频功能 `10de:22be`）/ NullMoth 驱动 / 内屏 BOE `2533:3214`

## 驱动能干什么（实测，不是文档摘抄）

```
Metal 设备   NVMTL over NVIDIA GeForce RTX 4060 Laptop GPU (NVK AD107-A)，Metal 3
BAR1         8192 MB（驱动日志 nvrm: b80 ... BAR1 8192 MB, VRAM 8188 MB）
硬解         H.264 ✅  HEVC ✅  ProRes ❌（正常）
硬编         ❌（Ada 编码器未实现）
```

网传「NullMoth 的 BAR1 只剩 256MB」在 2.6.6 上不成立，`ResizeGpuBars` 本来就不需要碰。

## 但 BAR 调整试过一次，黑屏，已回滚

显存拷贝带宽实测 **79.4 GB/s**（256MB blit，5 次取最优 3.38ms），
而 4060 Laptop 理论约 256 GB/s —— 恰好是 DDR5 双通道的水平。驱动日志也印证：

```
nvrm: b80 LOCAL+mapped memory -> system RAM (b79 placement)
```

说明显存分配落在系统内存里。按官方 HOW-IT-WORKS 的「安装后」表格改成
`ResizeGpuBars=13`（2^13 MB = 8 GB）/ `ResizeAppleGpuBars=-1` 后：

```
bar1: placing BAR1 8192 MB 0x7c00000000
boot screen: copied 2560x1600 ... in 17664 ms          ← 17.6 秒
nvdv: (BAR1 placed outside the console); registry held busy until the display is armed
boot raster: head 0..3 -> 0.000 Hz (not running / unknown)   ← 四个显示头全灭
```

**BAR1 一旦搬离固件原位置，NVKMS 就无法从原 framebuffer 接管内屏，heads 全部 not running → 黑屏。**
官方那句 "tested on the RTX 5060" 是台式单屏场景，MUX 直连内屏的笔记本不适用。

**结论：保持 `ResizeGpuBars=-1` / `ResizeAppleGpuBars=0`，接受 79 GB/s。**
回滚方式是把 ESP 上预放的 `config.plist.before-bar13` 拷回 `config.plist`（Windows 侧即可操作）。

## 刷新率与 HiDPI

- 驱动会报 240 Hz 模式，`CGDisplaySetDisplayMode(2560x1600@240)` 实测**成功、不黑屏**
- 但 240 Hz 下 **HiDPI 变体数为 0** → 只能二选一：`60Hz + 2x`（清晰）或 `240Hz + 1x`（UI 极小）
- 写 `DisplayProductID-3214.plist`（`scale-resolutions`）试图让窗口服务器在原生时序上生成 2x 变体，
  重启后**没有产生任何新模式** —— 驱动合成的假 EDID 下这套 override 被忽略（EDID 里尺寸只有 33×21 mm 就是证据）

## 核显 780M：没有驱动，别再找了

`1002:1900`（Phoenix / RDNA3 / gfx1103）。官方 NootedRed 兼容页原文：
只支持 Raven / Renoir（Vega），"Other iGPU generations (GCN < 5, RDNA) are not supported at all (yet)"。

- 自媒体说的「780M fork 已支持硬解/花屏/亮度」是**误传**（原文写的是 5800H 那批 Vega）
- amd-osx 版主 Edhawk：「780M isn't supported by NootedRed.kext, so it will never have full graphics acceleration」
- 唯一沾边的新项目 `lemonade-sdk/mac-amdgpu` 需要关闭 SIP + 苹果签发的 DriverKit entitlement，且走 PCI 独显路径

而且本机**内屏是 4060 经 MUX 直连**，核显即使驱动成功也只影响视频硬解与功耗，不影响桌面。

> 顺带：`AMDProbe.kext` 与 EC 风扇控制那条线见仓库根 README 与 `probe/`。
