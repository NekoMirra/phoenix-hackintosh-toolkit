# 内置摄像头：灯亮、零帧

> 硬件：Chicony `04F2:B78A`（UVC 标准相机），挂在 XHC0 根口 3（`0x61300000`）
> 结论：**macOS 26 的 UVC 栈与这颗模组在此平台上不兼容**，用 Windows 时摄像头正常。

## 现象

- 摄像头指示灯亮、系统能枚举、`system_profiler SPCameraDataType` 正常
- FaceTime / 照片 Booth 打开即「无视频」
- 自己写 `AVCaptureSession` 测：`startRunning()` 返回 true，但**收不到任何帧**

## 已排除的项（全部实测，不是推断）

| 排除项 | 依据 |
|---|---|
| 硬件/排线坏 | 同一颗摄像头在 Windows 下正常出画面 |
| 隐私权限 | `tccutil reset Camera` 后重新授权，`requestAccess → true` |
| 分辨率/带宽 | 七档分辨率（352×288 / 320×240 / 640×480 / 1280×720 …）**全部 0 帧** |
| alternate setting 选错 | alt 1→6（1020 / 1536 / 2040 / 2688 字节每微帧）全试过，全 0 帧 |
| 端口映射 | PRT3 ↔ `USBPorts.kext` 的 HS03，`UsbConnector=255`（内建），正确 |
| hub 级联 | 摄像头独占根口 3，不经 hub |
| 设备状态卡死 | 两次完整冷启动（断电 30 秒）后仍复现 |
| probe 协商值畸形 | 见下，数值全正常 |
| 内核补丁干扰 | config 里没有任何 USB/XHCI 补丁 |
| UVCProbeFix | 加载成功但补丁未生效（见下） |

> 一个必须记的坑：用 `sessionPreset = .high` 测不同分辨率是**假测试**，
> 它会把 `activeFormat` 顶回 1280×720，看起来「切了」其实没切。
> 必须 `lockForConfiguration` + `activeFormat` 显式设置。

## 卡在哪：协商正常，数据不进

```
[Probe] SET_CURR  request  MaxPayloadSize:0     MaxVideoFrameSize:1843200 dwClockFrequency:0
[Probe] GET_CURR  response MaxPayloadSize:2304  MaxVideoFrameSize:1843200 dwClockFrequency:15000000
Endpoint Alternate Setting 1..6 [maxPacketSize 128/512/1020/2816/3068/4992]
Stream Alternate Setting 6 pipe <IOUSBHostPipe>
[isoch-stream] bufferSize 2688 deviceSpeed 3 supportsXHCI Yes bInterval 1
[isoch-stream] re-read failure (null)      ← 反复
NativeProcessor { packetsReceived = 0 }
```

`1843200 = 1280×720×2`、`2304` payload、`15 MHz` clock —— **全是合理值**，
不属于 UVCProbeFix 修的那类畸形响应（那类会返回 `184549376` 这种荒谬数字）。

内核侧：

```
AppleUSBXHCIPipe: IOUSBHostPipe::abortGated: device 1 (HD Webcam) endpoint 0x81: aborting 3 requests
AppleUSBXHCIPipe: ... endpoint 0x83: aborting 1 requests
```

连**控制接口的 interrupt 端点 0x83** 都有请求永远不完成 → 不是驱动选错设置，
而是设备对 IN token 完全不回应。

## 试过的两个第三方方案

**UVCProbeFix**（DNMTechLabs，v0.3.1）：拆包核对后发现只适配
构建号 `25G83/25G229/25G241` 与 `174F:1176`（Lenovo IdeaPad S145 的 Syntek 摄像头），
本机是 `25G332` + `04F2:B78A`。它设计成 fail-closed（区段对不上就放弃），
装上后确实加载了、但补丁一条都没打，相机仍 0 帧 → 已 `Enabled=false` 归档。

**XHCILagFix**：它 hook 了 `AppleUSBXHCIIsochronousTransferRing::enqueueRequest`，
看起来极像元凶。关掉实测——**仍 0 帧**，而且副作用是鼠标键盘卡顿（它本来就在修 USB 延迟），
已恢复启用。这条线索可以排除。

## 现状与建议

需要摄像头时用 Windows。真要在这边用，外接一个普通 UVC 摄像头（几十块）基本都能跑，
问题出在这颗 Chicony 的固件协商，不是所有 UVC 设备都这样。
