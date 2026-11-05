# MT7922 Wi-Fi：从「能连不能上网」到校园网可用

> 硬件：MediaTek MT7922（`14c3:7922`，RZ616），M.2 2230，Wi-Fi + 蓝牙同一模块
> 系统：macOS 26.7.2（25G332）/ OpenCore 引导

这颗卡在 macOS 上没有原生驱动。本机前后试过 4 条路线，只有最后一条活下来，
活下来之后又花了整整两天修数据面（4-way 握手、组播解密、看门狗、门户认证）。

---

## 一、四条路线的真实结果

| 路线 | 形态 | 结果 |
|---|---|---|
| `AirportMtkWlan` 1.5.0 / 1.7.0（flxxxxddd） | 原生 IO80211 菜单 | ❌ 1.5.0 能扫能关联，但 AP 强制 PMF（`key check 80`）时 4-way 被拒；1.7.0 加了 WPA3-SAE 但 **attach 阶段 100% panic**（GP fault，落在 IOSkywalkFamily） |
| `SimpleMtkWlan`（laobamac / flxxxxddd） | Ethernet 后端 | ❌ panic（与 AirportMtkWlan 同匹配 `0x792214c3`，互抢 MMIO） |
| `MT7922SkyWalk` 1.2.64（qiqco） | 原生 | ❌ 扫描正常，关联失败 |
| **`itlmt7922`（chenhggu6475）** | **Ethernet 后端 + 客户端 App** | ✅ **可用**，代价是没有原生 Wi-Fi 菜单 |

**结论**：在 macOS 26 上，MT7922 想「不 panic」只能走 IOEthernet 路线。
原生菜单那条路（AirportMtkWlan）在 1.7.0 上是确定性 panic，不是概率问题
（用户实测 100%，推翻上游「热重启 1/5~1/20」的说法）。

> 另一条更冷门的路：macOS 26 自带的 `com.apple.AppleSunriseWLAN.dext` 的
> `IOPCIMatch` 里**本来就有 `0x792214c3`**，二进制里也有 `MTK/chips/mt7922/mt7922.c`
> 和完整的 `DriverKit_IO80211AWDL` 通道。理论上这才是真正「原生 + AirDrop」的路，
> 但系统只带了 MT7932 的固件（`IZUBA_*`），需要往签名系统卷里塞 MT7922 固件；
> 社区已推到「设备树起来、Wi-Fi 图标出现、但扫描不到任何 SSID」。
> 细节见 [open-issues.md](open-issues.md)。

---

## 二、itlmt7922 的三层数据面 bug（本次真正修掉的东西）

驱动默认状态下「能关联、能扫描、拿不到流量」。逐层拆开是三个独立的 bug。

### 1. 组播 / 广播帧没装 GTK（固件侧）

现象：`rxd` 冻结、`RX reject status=5(CIPHER) sec=0`，单播偶尔通、组播全丢。

根因：广播帧的 TA 是 BSSID，匹配的是 AP 的 WTBL 表项，而那张表里只有 PTK。
固件不会把 GTK 镜像给客户端，所以组播帧到驱动手上时是「没有密钥的密文」。

**踩过的坑（重要）**：第一次尝试是在 `M3_AP_WCID` 上「补装 GTK」，
结果把原本的 PTK 覆盖掉了 → `uni=0/43`、所有网络显示未连接。
**MTK 的装密钥命令是替换，不是追加**，在 AP 表项上装 GTK 等于废掉 PTK。

### 2. 软件 CCMP 解密的 AAD 构造错误（自己写的 codec）

改成「GTK 只留在内存 + 组播帧软件解密」后，第一版 296 帧全部 MIC 失败。

根因：AAD 里的 Frame Control 掩码位偏移算错了。正确做法（对齐 mac80211 `ccmp_gcmp_aad`）：

```c
uint16_t mfc = fc0 | (fc1 << 8);
mfc &= ~(0x3800u | 0x0070u);   // 清 Retry / PM / MoreData，清子类型低 3 位
mfc |= 0x4000u;                // 置 Protected
```

> **自洽陷阱**：单元测试端一开始复制了同一份错误掩码，导致「测试全绿、线上全红」。
> 修完必须用 RFC 3610 官方向量 + 独立实现的掩码做交叉验证，不能被测代码自己验自己。
> 另一个细节：CTR 块的 flags 是 `0x01`，不是 B_0 的 `0x59`。

### 3. 单播看门狗在强制门户上必然误判（逻辑 bug）

```c
// 原判据：15 秒内没收到单播且发过 ≥2 个 → 判定链路死，拆链路
if (!stRxUni && stTxUni >= 2) { ... }
```

在校园网强制门户上，未认证前除了 EAPOL 没有任何单播流量，
于是每 15 秒被自己拆一次链路（日志 `lvl 2: no unicast frame received in 15s`），
DHCP 永远跑不完。

修法：窗口 15s → **40s**，阈值 2 → **64**。

---

## 三、另外两个「看起来像 bug」的问题

**部分 5G 信道搜不到**：`itlmt7922_m2.cpp` 里扫描信道表硬编码，漏了中国合法的 DFS 段
52/56/60/64。补上后 `channels=26`（原 22）。100–144 没加，避免整表被固件拒绝。

**中文 SSID 显示为空**：`wifiNets()` 用 `OSString::withCString()` 发布，
GBK 字节不是合法 UTF-8 → 整串变空。改成非法字节转 `\xNN` 转义。

修完的 kext 版本仍标 0.2.2，但二进制与官方不同（含三项补丁）。

---

## 四、客户端 App 的自动连接改造

`ItlWiFi7922`（`local.experimental.ItlWiFi7922.enterprise-test1`）是这颗卡唯一的连接入口，
但它**启动时不会扫描**，`autoJoin()` 因为 `st.nets` 为空永远匹配不到网络 → 每次开机都得手点。

改源码 `app/ItlWiFi7922.swift`（4 处）：

1. 新增 `LastStore`，把上次连成功的 SSID 写进 `~/Library/Application Support/ItlWiFi7922/last.json`
2. `init()` 里 1.5s 后主动 `scan()` + `autoJoin()`（**已连接时跳过**，扫描会让网卡瞬时 `inactive`）
3. 新增 `maybeAutoScan()`：未连接时 4s 起、×1.6 退避、上限 30s
4. `autoJoin()` 优先 last SSID，其次按信号强度；失败可重试，连续 5 次才放弃

另外加了单实例保护（`NSRunningApplication.runningApplications(withBundleIdentifier:)`）——
之前两个实例互相抢设备，正是 en2 变 `inactive` 的原因。

实测：en2 无 IP 状态下只启动一个实例，**5 秒内自动连回**。

## 五、辅助：登录看护

`tools/wifi-autoconnect.sh` + `~/Library/LaunchAgents/local.itlmt7922.autoconnect.plist`：
en2 没有 IPv4 且 App 未运行时拉起 App，`RunAtLoad` + 每 60 秒复查。

> 注意：沙箱里 `launchctl bootstrap` 会报 `5: Input/output error`，
> 必须 `launchctl asuser 501 launchctl bootstrap gui/501 <plist>` 才能注册。

---

## 六、当前状态

```
接口：en2（Ethernet Adapter），非 en0
能力：2.4G/5G 扫描、WPA2-PSK、WPA2/WPA3 混合、VHT80 2SS、校园网强制门户
上限：无 HE(802.11ax)、无原生菜单、**无 AWDL（所以没有 AirDrop / 接力）**
```

> 想要原生 Wi-Fi 菜单 + AirDrop，目前只有换 Broadcom 卡（BCM94360NG，同为 M.2 2230）
> 或等 Apple `AppleSunriseWLAN.dext` 那条线打通。详见 [open-issues.md](open-issues.md)。
