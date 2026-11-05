# EFI 快照（OpenCore）

> 导出时间：2026-11-05 · 系统：macOS 26.7.2 (25G332) · 机型：MacBookPro16,4（SMBIOS）
> 这是**能引导进系统的那份配置**，直接用 OpenCore 引导，不是备份压缩包。

## ⚠️ 三码已置空

`OC/config.plist` 里以下字段已换成占位值，**必须填回你自己的**，否则 iCloud / iMessage 登不上：

| 字段 | 占位值 | 说明 |
|---|---|---|
| `PlatformInfo → Generic → SystemSerialNumber` | `C02XXXXXXXXXX` | 用 `macserial -m MacBookPro16,4` 生成 |
| `PlatformInfo → Generic → MLB` | `C02XXXXXXXXXXXXXXX` | 必须与上面的序列号**同批派生** |
| `PlatformInfo → Generic → SystemUUID` | `00000000-0000-4000-8000-000000000000` | 随机 UUID 即可 |
| `PlatformInfo → Generic → ROM` | `000000000000` | 填 en0（板载网卡）的真实 MAC |

顶层 `NVRAM → Add → 4D1EDE05-…` 里的同名四项也一起清空了，填的时候**两处都要改**。

> 三码不影响能否引导，只影响 iServices。想先试能不能开机，直接灌进去就行。

## 目录

```
efi/
├── Boot/BOOTx64.efi
└── OC/
    ├── OpenCore.efi
    ├── config.plist              ← 已脱敏
    ├── ACPI/   11 个 AML
    ├── Drivers/ 4 个 UEFI 驱动
    ├── Kexts/  28 个 kext
    ├── Resources/                OpenCanopy 主题（GoldenGate + 自定义背景）
    └── Tools/  NullMothSafe.efi
```

**未包含**：`EFI/Microsoft`（Windows 引导，与本机无关）、`EFI/HackBGRT`（开机图替换）。

## ACPI

`SSDT-BATS.aml`, `SSDT-BATT.aml`, `SSDT-Disable_Network_GPP6.aml`, `SSDT-EC.aml`, `SSDT-HPET.aml`, `SSDT-PLUG-ALT.aml`, `SSDT-PNLF.aml`, `SSDT-RLAN.aml`, `SSDT-USB-Reset.aml`, `SSDT-USBX.aml`, `SSDT-XOSI.aml`

其中 **`SSDT-RLAN.aml`** 是本项目自己写的：给 `_SB.PCI0.GPP5.RLAN` 加 `_DSM` 返回
`built-in = <01>`。实测该属性会被更上层统一写回 0（见 [../docs/apple-id.md](../docs/apple-id.md)），
留着不影响引导，介意可以关掉。

## Drivers

`HfsPlus.efi`, `OpenCanopy.efi`, `OpenRuntime.efi`, `ResetNvramEntry.efi`

## Kexts

| Kext | Identifier | Version |
|---|---|---|
| `AMDProbe.kext` | `wtf.local.AMDProbe` | 1.0.0 |
| `AMDRyzenCPUPowerManagement.kext` | `wtf.spinach.AMDRyzenCPUPowerManagement` | 0.7.2 |
| `AMFIPass.kext` | `com.dhinakg.AMFIPass` | 1.4.1 |
| `AppleALC.kext` | `as.vit9696.AppleALC` | 1.9.9 |
| `AppleMCEReporterDisabler.kext` | `org.xlnc.disabler.MCEReporter` | 1.2 |
| `BlueToolFixup.kext` | `as.acidanthera.BlueToolFixup` | 2.7.2 |
| `BrightnessKeys.kext` | `as.acidanthera.BrightnessKeys` | 1.0.4 |
| `Lilu.kext` | `as.vit9696.Lilu` | 1.7.3 |
| `MtkBtIdMask.kext` | `com.yyavic.MtkBtIdMask` | 1.0.0 |
| `NVMeFix.kext` | `org.acidanthera.NVMeFix` | 1.1.4 |
| `RealtekRTL8111.kext` | `com.insanelymac.RealtekRTL8111` | 2.4.2 |
| `RestrictEvents.kext` | `as.vit9696.RestrictEvents` | 1.1.7 |
| `SMCAMDProcessor.kext` | `wtf.spinach.SMCAMDProcessor` | 1.0.1 |
| `SMCBatteryManager.kext` | `ru.usrsse2.SMCBatteryManager` | 1.3.9 |
| `SMCLightSensor.kext` | `ru.usrsse2.SMCLightSensor` | 1.3.9 |
| `SimpleHDA.kext` | `cn.laobamac.SimpleHDA` | 1.0.0 |
| `SimpleMtkBtFw.kext` | `com.laobamac.SimpleMtkBtFw` | 1.0.0 |
| `SimpleMtkBtPatcher.kext` | `com.laobamac.SimpleMtkBtPatcher` | 1.0.0 |
| `USBPorts.kext` | `com.Headsoft.USBPorts` | 1.0 |
| `UVCProbeFix.kext` | `com.dnmtechlabs.UVCProbeFix` | 0.3.1 |
| `UVCPropMerge.kext` | `local.uvcpropmerge` | 1.0 |
| `VirtualSMC.kext` | `as.vit9696.VirtualSMC` | 1.3.9 |
| `VoodooI2C.kext` | `com.alexandred.VoodooI2C` | 2.9.1 |
| `VoodooI2CHID.kext` | `com.alexandred.VoodooI2CHID` | 1.0 |
| `VoodooPS2Controller.kext` | `as.acidanthera.voodoo.driver.PS2Controller` | 2.3.8 |
| `WhateverGreen.kext` | `as.vit9696.WhateverGreen` | 1.7.2 |
| `XHCILagFix.kext` | `as.local.XHCILagFix` | 0.1.0 |
| `itlmt7922.kext` | `local.experimental.itlmt7922` | 0.2.2 |

### 本项目自研 / 改过的

| Kext | 说明 |
|---|---|
| `AMDProbe.kext` | SMU 邮箱直读（功耗墙 / 温度），源码在 `../probe/` |
| `XHCILagFix.kext` | 修本机 USB 延迟（关掉会出现鼠标键盘卡顿） |
| `MtkBtIdMask.kext` | plist-only，把 `13D3:3585` 伪装成 `0489:E0D8` |
| `UVCPropMerge.kext` | plist-only，给摄像头注入 `UVCCameraHideControls`（实验，当前无效） |
| `USBPorts.kext` | 本机 USB 端口映射 |
| `itlmt7922.kext` 0.2.2 | 在上游基础上补了 5G DFS 信道 52–64、GBK SSID 转义、单播看门狗阈值 |
| `SimpleHDA.kext` / `SimpleMtkBtFw` / `SimpleMtkBtPatcher` | laobamac 的作品，解决 macOS 26 没有 AppleHDA、以及 MT7922 蓝牙固件 |

### 第三方

`Lilu` / `VirtualSMC` / `WhateverGreen` / `AppleALC` / `RestrictEvents` / `NVMeFix` /
`BrightnessKeys` / `BlueToolFixup` / `VoodooI2C` / `VoodooPS2Controller` /
`SMCBatteryManager` / `SMCLightSensor` / `AMDRyzenCPUPowerManagement` / `SMCAMDProcessor` /
`AMFIPass` / `AppleMCEReporterDisabler` / `RealtekRTL8111`，
版权归各自作者，按原许可分发（多为 GPL / BSD / Apache-2.0）。版本见上表。

## 恢复到一个新 ESP

```sh
# 1. 挂载 ESP（macOS 下编号每次开机都会变，先确认）
diskutil list | grep -i efi
sudo diskutil mount disk0s1

# 2. 拷进去（先备份原有 EFI！）
cp -R efi/Boot /Volumes/EFI/EFI/
cp -R efi/OC   /Volumes/EFI/EFI/

# 3. 填回自己的三码（两处：PlatformInfo.Generic 与 NVRAM.Add.4D1EDE05）
# 4. 校验
plutil -lint /Volumes/EFI/EFI/OC/config.plist
```

> 这份 EFI 是按 25G332 调的。换 macOS 大版本后，`itlmt7922` / 蓝牙那几个 kext
> 以及 `SecureBootModel` / `ResizeGpuBars` 都可能要重新确认。

## 已知坑（详细见 ../docs）

- `ResizeGpuBars` 必须 `-1`，改成 13 会黑屏（四个显示头全灭）
- 改完 Wi-Fi / 蓝牙 kext 要**关机断电 10 秒**，热重启有 1/5~1/20 panic 概率
- `Misc → NVRAM → WriteFlash` 必须是 `true`，否则三码写不进 NVRAM
