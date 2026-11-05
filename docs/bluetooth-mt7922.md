# MT7922 蓝牙：四件套 + 一个标记文件

> 这台机器的蓝牙折腾了整整三天，先后得出过三次「软件路径穷尽、只能换 USB 蓝牙」的错误结论。
> 最后通了。**关键不是缺驱动，而是 BlueTool 在按 Broadcom 的方式刷机。**

## 硬件事实

- 蓝牙是 **USB 通路**（`13d3:3585`，AzureWave），跟 PCIe 的 Wi-Fi 完全独立
- USB 描述符：`bDeviceClass=0xEF`（IAD 复合），3 个接口全部 `class=0xE0/sub=1/proto=1`（标准蓝牙控制器类）
- 设备名 `Wireless_Device`，挂在 XHC0 根口 4

## 最终可用的配方（缺一不可）

`Kernel → Add` 顺序：

```
Lilu.kext
SimpleMtkBtFw.kext        # 固件加载器（固件内嵌在二进制里，1.3MB）
SimpleMtkBtPatcher.kext   # Lilu 插件
MtkBtIdMask.kext          # plist-only，把 13D3:3585 伪装成 0489:E0D8
BlueToolFixup.kext        # 2.7.2，让 BlueTool 跳过 Broadcom 的刷机脚本
```

再加一个**文件**（不是 kext）：

```sh
sudo touch /etc/bluetool/SkipBluetoothAutomaticFirmwareUpdate
```

固件放到 `/etc/bluetool/BT_RAM_CODE_MT7922_1_1_hdr.bin`（517398 字节）。

**必须冷启动**：关机 → 等 10 秒 → 开机。热重启不加载固件。

## 为什么之前一直失败：BlueTool 的 boot script 返回 3

失败时的日志（`log show --predicate 'process == "BlueTool"'`）：

```
BlueTool: USB Bluetooth Host Controller 0xE0D8 Firmware Version v100 BCD Device 0x0100
BlueTool: Could not USB DFU detach for device ... error 0xE000404F
BlueTool: updateFirmwareInSerialFlash res=3
BlueTool: builtin script completed with result 3
bluetoothd: BlueTool failed to run boot script with result 3
```

拆开看：`0489:E0D8` 这个 ID 在 macOS 眼里是 **Broadcom 系**，于是 bluetoothd 去跑
「串行 Flash 固件更新」的内置脚本；这颗联发科芯片当然不会响应 DFU detach，
脚本返回 3，**bluetoothd 直接放弃上电**，控制器永远停在
`Chipset: BCM_4350C2 / Transport: UART / Address: NULL`。

> 这个 `BCM_4350C2` 是 macOS「没有可用传输层」时的**占位值**，不是硬件信息。
> 我一度以为它是 BlueToolFixup 合成的假控制器，白查了一轮。

修好之后同一行变成：

```
BlueTool: updateFirmwareInSerialFlash res=0
BlueTool: builtin script completed with result 0
```

## 成功后的样子

```
Address: 94:BB:43:89:DE:21     State: On
Chipset: THIRD_PARTY_DONGLE     Firmware: v9489 c6166
Transport: USB
Supported services: HFP AVRCP A2DP HID Braille LEA AACP GATT SerialPort
```

`THIRD_PARTY_DONGLE` 是正常结果（走基础蓝牙栈），耳机/键鼠/AirPods 音频都没问题。
注意 MAC 与 Wi-Fi 连号（`en2 = 94:bb:43:89:de:20`），说明确实是同一个 MT7922 模块的两半。

## 成功判定的中间态（用来定位卡在哪一步）

| 观察点 | 含义 |
|---|---|
| `ioreg` 里设备出现 `BT_ACL_If@0` / `BT_SCO_If@1` / `BT_ISO_If@2` | 固件已写入、芯片已切到工作模式 |
| 设备有 `FirmwareLoaded = Yes` | 同上（驱动打的标记） |
| `blueutil` / `system_profiler` 里 `Address` 仍为 NULL | 卡在 BlueTool，看 boot script result |
| `result 3` | Broadcom 刷机脚本失败 → 检查 `SkipBluetoothAutomaticFirmwareUpdate` 与 BlueToolFixup |

## 排除过但无效的尝试（别重复）

- 换伪装 ID：`0489:E0D8`（Foxconn）/ `0E8D:7922`（MediaTek 原厂）都试过，**不是 ID 问题**
- 关掉 BlueToolFixup：`bluetoothExternalDongleFailed` 会稳定成 `00`，但控制器依旧不上电
- NVRAM 变量 `bluetoothInternalControllerInfo=14×00`、`bluetoothExternalDongleFailed=00`：
  属于旧路径，本机实测与成败无关
- 只用 `SimpleMtkBtFw` 不开 `BlueToolFixup`：固件能进，但 BlueTool 照样跳过不了刷机脚本

## 冷启动是硬要求

MT7922 的两半（Wi-Fi / 蓝牙）在热重启时都可能保留脏状态：
Wi-Fi 侧是 1/5~1/20 概率 panic，蓝牙侧是固件不重新加载。
**改完这类驱动，一律关机断电 10 秒再开。**
