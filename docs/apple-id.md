# Apple ID `-20970`：五轮误判之后

> 最终结论：**根因是陈旧的 akd 认证缓存**，不是三码不配套，也不是 en0 没内建。

## 症状

系统设置里登录 Apple ID，一律「发生未知错误」，`akd` 日志：

```
AKAuthenticationServerError -20970
```

## 失败时的日志长什么样

```
21:08:20.476  urlConfigurationForKey: gsService → FetchURLBag（0.000044s，走缓存）
21:08:21.107  sent request, body S 2993
21:08:21.569  received response, status 200          ← 服务器其实回应了
21:08:21.570  AppleIDAuthSupport: setError: 2:selected protocol key missing
21:08:21.570  Invalid/missing value for key acname: (null)
21:08:21.572  SRP authentication with server failed! Code=2 → -20970
```

关键在两点：`FetchURLBag` 只花了 **0.000044 秒**（完全走旧缓存），
以及服务器返回 200 但响应体里**没有客户端预期的 SRP 协议字段**。

## 真正生效的一步

```sh
sudo rm -rf ~/Library/Caches/com.apple.akd
sudo rm -rf ~/Library/Caches/com.apple.AppleIDAuthSupport
sudo rm -rf /var/db/akd
sudo killall akd
```

清完立刻就能登上，**网络没换、用户没换、配置没改**。

## 那之前五轮改的是什么（记录，避免再走）

| 轮次 | 假设 | 结果 |
|---|---|---|
| 1 | NVRAM 里 MLB 没写进去 | 查出 `Misc→NVRAM→WriteFlash` 段整段缺失（默认 false），补上后写入链路才通 |
| 2 | config 里 MLB 改了但没生效 | 发现改动被插进了**误嵌套在 `Misc` 里的 NVRAM 段**，OC 只读顶层 `NVRAM`，等于白改 |
| 3 | 序列号与 MLB 不配套 | 用 `macserial -m <model>` 重新派生整套三码（配套 serial + MLB + UUID），确实该换 |
| 4 | 冒充带 T2 的机型拿不出硬件证明 | 换 `iMac19,1` → **不在 macOS 26 支持列表，直接禁止符号启动**（已回滚） |
| 5 | en0 没有 `built-in` | DP / kext merge / ACPI `_DSM` 三法全试，属性被上层统一写回 0；**但清除缓存后照样能登录** |

**这台机器最终可用的身份组合**（数值已脱敏）：

```
SMBIOS           MacBookPro16,4（macOS 26 支持列表内的 6 款之一，全部带 T2）
serial / MLB     由 macserial 同批派生，互相配套
ROM              = en0（Realtek RTL8111）的真实 MAC
en0 built-in     未注入成功，不影响 iCloud 登录
```

> macOS 26 支持的 Intel 机型只有 6 款：MBP16" 2019、MBP13" 2020 四雷雳、
> iMac 27" 2020、Mac mini 2018、Mac Pro 2019、iMac Pro 2017。
> **这 6 款全带 T2**，「换非 T2 机型躲开 BAA」在 macOS 26 上不存在。

## iMessage：不是机器的问题，是账号要人工验证

iCloud 登上之后 iMessage 登录 10 秒自动退出。从
`~/Library/Preferences/com.apple.identityservicesd.plist` 的 `services` 字段
（gzip + bplist，要 `gzip.decompress` 后 `plistlib.loads`）能读到苹果的原话：

```
Registration = {
  AlertInfo: {
    title: "你目前无法在此 Mac 上登录 iMessage 信息。",
    body:  "...请联系 Apple 支持并提供以下代码。顾客代码：XXXX-XXXX-XXXX..."
  }
  ErrorCode: 20, InternalErrorCode: 31, Status: -1
}
RegistrationFailureError = 31
```

同一个文件里 `multiplex1`（Apple ID 基础 IDS 通道）状态是 **Registered 成功**，
所以 iCloud 正常、只有 madrid/ess（iMessage / FaceTime）被拒。

**处理方式只有一条**：拿顾客代码联系 Apple 支持（`getsupport.apple.com` → Apple ID →
iMessage/FaceTime），或在弹窗给的 `apple.com/support/validation` 链接里提交。
账号是新注册的，新号被 iMessage 风控拦是常见现象，**和黑苹果配置无关**。

> `ReRegisteredForDevices`（本机曾到 1924）是**服务端下发的计数**：
> 本地改 0 后重启会被原样还原（连 hash 都一样）。它是旁证，不是主因。
> 另外**不要连续重试**，每次失败都会让计数继续涨。

## 经验

1. `-20970` 不等于身份不对。先清认证缓存，再谈改配置。
2. 改 OC 的 NVRAM 一定要用 **顶层** `d['NVRAM']`，不是 `d['Misc']['NVRAM']`；
   改完在原始 XML 里 grep 确认落在正确段落。
3. `UpdateSMBIOSMode` 只管 SMBIOS 表，不管 NVRAM 落盘；真正决定写不写的是
   `Misc → NVRAM → WriteFlash`。
4. 平台 UUID 由序列号派生，换序列号它会跟着变，`SystemUUID` 与 ioreg 不一致是正常现象。
