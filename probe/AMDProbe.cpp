/*
 * AMDProbe.kext —— 为 AMD Phoenix(8845H) 打通 SMN / SMU 通道
 *
 * 设计原则：开机时【不做任何写操作】。只找到 0:0.0 主桥，把 SMN 间接访问
 * 和 SMU 邮箱收发暴露给用户态。所有限值调整由用户态工具按需发起，
 * 这样开机风险为零，出问题只需重启。
 *
 * SMN 访问：PCI 配置空间 0xB8 = 索引, 0xBC = 数据（family 17h+ 标准做法）
 * SMU 邮箱（Phoenix, FAM_PHOENIX）：
 *     消息口 0x3B10528 / 应答口 0x3B10578 / 参数区 0x3B10998
 */

#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/pci/IOPCIDevice.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOLocks.h>
#include <IOKit/IOPlatformExpert.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <mach/mach_time.h>

#define SMU_MSG_ADDR        0x3B10528
#define SMU_REP_ADDR        0x3B10578
#define SMU_ARG_ADDR        0x3B10998
#define SMN_IDX_REG         0xB8
#define SMN_DAT_REG         0xBC

#define REP_MSG_OK          0x01

class AMDProbe;

#pragma mark - 用户态客户端

class AMDProbeClient : public IOUserClient {
    OSDeclareDefaultStructors(AMDProbeClient)
private:
    AMDProbe *fDriver;
    task_t    fTask;
public:
    virtual bool initWithTask(task_t owningTask, void *securityID,
                              UInt32 type, OSDictionary *props) override;
    virtual bool start(IOService *provider) override;
    virtual IOReturn clientClose() override;
    virtual IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                                    IOExternalMethodDispatch *dispatch,
                                    OSObject *target, void *reference) override;
};

#pragma mark - 驱动本体

class AMDProbe : public IOService {
    OSDeclareDefaultStructors(AMDProbe)
public:
    IOPCIDevice *fPci;
    IOLock      *fLock;
    uint32_t     fFamily;
    uint32_t     fModel;
    uint32_t     fSmuVersion;
    bool         fSmuOk;
    IOACPIPlatformDevice *fEcDev;   // \_SB.INOU —— 同方模具 EC 读写接口
    int          fEcQuota;          // EC 写入配额，arm 后才有值，用完即锁

    virtual bool start(IOService *provider) override;
    virtual void stop(IOService *provider) override;
    virtual IOReturn newUserClient(task_t owningTask, void *securityID, UInt32 type,
                                   OSDictionary *properties, IOUserClient **handler) override;

    bool     ensurePci();
    uint32_t smnRead(uint32_t addr);
    void     smnWrite(uint32_t addr, uint32_t val);
    uint32_t smuSend(uint32_t msg, uint32_t *a, bool *ok);
    bool     smuTest();

    bool     ensureEc();
    bool     ecRead(uint16_t addr, uint8_t *out);
    bool     ecWrite(uint16_t addr, uint8_t val);
    void     ecArm(uint64_t ignored);
};

OSDefineMetaClassAndStructors(AMDProbe, IOService)

static const int kEcWriteQuota = 32;   // 每次 arm 最多允许 32 次写入

static void cpuidGet(uint32_t leaf, uint32_t *a, uint32_t *b, uint32_t *c, uint32_t *d) {
    __asm__ __volatile__("cpuid"
                         : "=a"(*a), "=b"(*b), "=c"(*c), "=d"(*d)
                         : "a"(leaf), "c"(0));
}

// 延迟查找主机桥：开机早期 PCI 可能未就绪，用户态首次访问时再补找
// 判定是否为 AMD 主机桥。
// 注意：IORegistry 里 class-code 是 3 字节 [progIF, subClass, baseClass]，
// 不是 4 字节；之前按 uint32 读并比较 0x060000 永远不成立。
static bool amdHostBridge(IOPCIDevice *pci) {
    OSData *vi = OSDynamicCast(OSData, pci->copyProperty("vendor-id"));
    bool ok = false;
    if (vi && vi->getLength() >= 4) {
        uint32_t vid = *(const uint32_t *)vi->getBytesNoCopy();
        ok = (vid == 0x1022);                  // AMD
    }
    if (vi) vi->release();
    if (!ok) return false;

    OSData *cc = OSDynamicCast(OSData, pci->copyProperty("class-code"));
    ok = false;
    if (cc && cc->getLength() >= 3) {
        const uint8_t *b = (const uint8_t *)cc->getBytesNoCopy();
        ok = (b[2] == 0x06 && b[1] == 0x00);   // base=0x06 bridge, sub=0x00 host bridge
    }
    if (cc) cc->release();
    return ok;
}

// pcidebug 形如 "0:0:0"，用来精确定位 bus0/dev0/fn0
static bool pciIsBus0Dev0(IOPCIDevice *pci) {
    OSObject *o = pci->copyProperty("pcidebug");
    OSString *d = OSDynamicCast(OSString, o);
    bool ok = false;
    if (d) {
        const char *c = d->getCStringNoCopy();
        if (c) ok = (c[0]=='0' && c[1]==':' && c[2]=='0' && c[3]==':' && c[4]=='0');
        d->release();
    } else if (o) o->release();
    return ok;
}

// 延迟查找主机桥：开机早期 PCI 可能未就绪，用户态首次访问时再补找
bool AMDProbe::ensurePci() {
    if (fPci) return true;

    OSDictionary *match = IOService::serviceMatching("IOPCIDevice");
    if (!match) return false;

    // 第一轮：AMD 主机桥且位于 0:0:0（SMN 窗口就在这个设备上）
    OSIterator *iter = IOService::getMatchingServices(match);
    if (iter) {
        OSObject *obj;
        while ((obj = iter->getNextObject())) {
            IOPCIDevice *pci = OSDynamicCast(IOPCIDevice, obj);
            if (pci && amdHostBridge(pci) && pciIsBus0Dev0(pci)) { fPci = pci; break; }
        }
        iter->release();
    }

    // 第二轮：退一步，任意 AMD 主机桥
    if (!fPci) {
        iter = IOService::getMatchingServices(match);
        if (iter) {
            OSObject *obj;
            while ((obj = iter->getNextObject())) {
                IOPCIDevice *pci = OSDynamicCast(IOPCIDevice, obj);
                if (pci && amdHostBridge(pci)) { fPci = pci; break; }
            }
            iter->release();
        }
    }

    match->release();
    return fPci != nullptr;
}


// ---- EC 访问：同方/机械革命模具通过 ACPI 方法 \_SB.INOU.ECRR / ECRW 读写 EC RAM ----

bool AMDProbe::ensureEc() {
    if (fEcDev) return true;
    IORegistryEntry *e = IORegistryEntry::fromPath("/_SB/INOU", gIOACPIPlane);
    if (!e) e = IORegistryEntry::fromPath("/INOU", gIOACPIPlane);
    fEcDev = OSDynamicCast(IOACPIPlatformDevice, e);
    return fEcDev != nullptr;
}

// 读一个 EC 字节。addr 为 16 位（同方 EC 支持 0x0000-0x0FFF 空间）
bool AMDProbe::ecRead(uint16_t addr, uint8_t *out) {
    if (!ensureEc()) return false;
    OSNumber *arg = OSNumber::withNumber((uint32_t)addr, 32);
    if (!arg) return false;
    UInt32 val = 0;
    OSObject *params[1] = { arg };
    IOReturn r = fEcDev->evaluateInteger("ECRR", &val, params, 1);
    arg->release();
    if (r != kIOReturnSuccess) return false;
    *out = (uint8_t)val;
    return true;
}

bool AMDProbe::ecWrite(uint16_t addr, uint8_t val) {
    if (!ensureEc()) return false;
    if (fEcQuota <= 0) return false;
    fEcQuota--;

    OSNumber *a0 = OSNumber::withNumber((uint32_t)addr, 32);
    OSNumber *a1 = OSNumber::withNumber((uint32_t)val, 32);
    if (!a0 || !a1) { if (a0) a0->release(); if (a1) a1->release(); return false; }
    OSObject *params[2] = { a0, a1 };
    IOReturn r = fEcDev->evaluateObject("ECRW", nullptr, params, 2);
    a0->release(); a1->release();
    return r == kIOReturnSuccess;
}

void AMDProbe::ecArm(uint64_t seconds) {
    (void)seconds;
    fEcQuota = kEcWriteQuota;
}

bool AMDProbe::start(IOService *provider) {
    if (!IOService::start(provider)) return false;

    fPci = nullptr;
    fSmuOk = false;
    fSmuVersion = 0;
    fLock = IOLockAlloc();
    if (!fLock) return false;

    // CPU family / model
    uint32_t a, b, c, d;
    cpuidGet(1, &a, &b, &c, &d);
    uint32_t baseFamily = (a >> 8) & 0xF;
    uint32_t baseModel  = (a >> 4) & 0xF;
    fFamily = (baseFamily == 0xF) ? (baseFamily + ((a >> 20) & 0xFF)) : baseFamily;
    fModel  = (baseFamily == 0xF) ? (baseModel | (((a >> 16) & 0xF) << 4)) : baseModel;

    // 尽力在启动阶段找主桥；找不到也无妨，用户态打开时会再找一次
    ensurePci();

    char buf[64];
    snprintf(buf, sizeof(buf), "0x%X", fFamily);
    setProperty("CPUFamily", buf);
    snprintf(buf, sizeof(buf), "0x%X", fModel);
    setProperty("CPUModel", buf);
    setProperty("HostBridgeFound", fPci ? true : false);

    if (fPci) {
        // 只读探测：确认 SMN 窗口可访问。开机阶段绝不写 SMU，
        // 所有 SMU 操作都等用户态发起，保证开机零风险。
        uint32_t probe = smnRead(0x0);
        snprintf(buf, sizeof(buf), "0x%08X", probe);
        setProperty("SMNProbe0", buf);
        setProperty("SMUOnline", false);   // 由用户态 amdctl info 现场测试
    }

    registerService();
    IOLog("AMDProbe: family=%x model=%x pci=%s smu=%s\n",
          fFamily, fModel, fPci ? "yes" : "no", fSmuOk ? "yes" : "no");
    return true;
}

void AMDProbe::stop(IOService *provider) {
    if (fLock) { IOLockFree(fLock); fLock = nullptr; }
    IOService::stop(provider);
}

IOReturn AMDProbe::newUserClient(task_t owningTask, void *securityID, UInt32 type,
                                 OSDictionary *properties, IOUserClient **handler) {
    ensurePci();   // 用户态此刻已启动完毕，PCI 一定就绪
    AMDProbeClient *client = new AMDProbeClient;
    if (!client) return kIOReturnNoMemory;
    if (!client->initWithTask(owningTask, securityID, type, properties)) {
        client->release();
        return kIOReturnError;
    }
    if (!client->attach(this)) { client->release(); return kIOReturnError; }
    if (!client->start(this)) { client->detach(this); client->release(); return kIOReturnError; }
    *handler = client;
    return kIOReturnSuccess;
}

uint32_t AMDProbe::smnRead(uint32_t addr) {
    if (!ensurePci()) return 0xFFFFFFFF;
    fPci->configWrite32(SMN_IDX_REG, addr);
    return fPci->configRead32(SMN_DAT_REG);
}

void AMDProbe::smnWrite(uint32_t addr, uint32_t val) {
    if (!ensurePci()) return;
    fPci->configWrite32(SMN_IDX_REG, addr);
    fPci->configWrite32(SMN_DAT_REG, val);
}

// 返回应答值；ok 表示是否在超时内拿到非零应答
uint32_t AMDProbe::smuSend(uint32_t msg, uint32_t *a, bool *ok) {
    if (ok) *ok = false;
    if (!fPci) return 0;

    smnWrite(SMU_REP_ADDR, 0);
    for (int i = 0; i < 6; i++) smnWrite(SMU_ARG_ADDR + 4 * i, a[i]);
    smnWrite(SMU_MSG_ADDR, msg);

    uint32_t rep = 0;
    for (int i = 0; i < 2000; i++) {          // 最多约 200ms
        rep = smnRead(SMU_REP_ADDR);
        if (rep != 0) break;
        IODelay(100);
    }
    if (rep == 0) return 0;                    // 超时，绝不无限等待
    for (int i = 0; i < 6; i++) a[i] = smnRead(SMU_ARG_ADDR + 4 * i);
    if (ok) *ok = true;
    return rep;
}

bool AMDProbe::smuTest() {
    IOLockLock(fLock);
    uint32_t a[6] = {0};
    smnWrite(SMU_REP_ADDR, 0);
    smnWrite(SMU_ARG_ADDR, 0x47);
    uint32_t back = smnRead(SMU_ARG_ADDR);
    if (back != 0x47) { IOLockUnlock(fLock); return false; }  // PCI 配置空间不可写
    bool ok = false;
    uint32_t rep = smuSend(0x01, a, &ok);   // TestMessage
    IOLockUnlock(fLock);
    return ok && (rep == REP_MSG_OK);
}

#pragma mark - 客户端实现

OSDefineMetaClassAndStructors(AMDProbeClient, IOUserClient)

bool AMDProbeClient::initWithTask(task_t owningTask, void *securityID,
                                  UInt32 type, OSDictionary *props) {
    if (!IOUserClient::initWithTask(owningTask, securityID, type, props)) return false;
    fDriver = nullptr;
    fTask = owningTask;
    return true;
}

bool AMDProbeClient::start(IOService *provider) {
    if (!IOUserClient::start(provider)) return false;
    fDriver = OSDynamicCast(AMDProbe, provider);
    return fDriver != nullptr;
}

IOReturn AMDProbeClient::clientClose() {
    terminate();
    return kIOReturnSuccess;
}

/*
 * 选择器（标量参数，最多 6 进 6 出）：
 *   0 info       -> [family, model, smuOnline, smuVersion, 0, 0]
 *   1 smnRead    <- addr            -> [val]
 *   2 smnWrite   <- addr, val
 *   3 smuSend    <- msg, a0..a5     -> [rep, a0..a5]
 */
IOReturn AMDProbeClient::externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                                        IOExternalMethodDispatch *dispatch,
                                        OSObject *target, void *reference) {
    if (!fDriver) return kIOReturnNotReady;

    switch (selector) {
    case 0: {
        if (args->scalarOutputCount < 4) return kIOReturnBadArgument;
        args->scalarOutput[0] = fDriver->fFamily;
        args->scalarOutput[1] = fDriver->fModel;
        args->scalarOutput[2] = fDriver->fSmuOk ? 1 : 0;
        args->scalarOutput[3] = fDriver->fSmuVersion;
        return kIOReturnSuccess;
    }
    case 1: {
        if (args->scalarInputCount < 1 || args->scalarOutputCount < 1) return kIOReturnBadArgument;
        args->scalarOutput[0] = fDriver->smnRead((uint32_t)args->scalarInput[0]);
        return kIOReturnSuccess;
    }
    case 2: {
        if (args->scalarInputCount < 2) return kIOReturnBadArgument;
        fDriver->smnWrite((uint32_t)args->scalarInput[0], (uint32_t)args->scalarInput[1]);
        return kIOReturnSuccess;
    }
    case 3: {
        if (args->scalarInputCount < 7 || args->scalarOutputCount < 7) return kIOReturnBadArgument;
        uint32_t a[6];
        for (int i = 0; i < 6; i++) a[i] = (uint32_t)args->scalarInput[1 + i];
        bool ok = false;
        uint32_t rep;
        IOLockLock(fDriver->fLock);
        rep = fDriver->smuSend((uint32_t)args->scalarInput[0], a, &ok);
        IOLockUnlock(fDriver->fLock);
        args->scalarOutput[0] = rep;
        for (int i = 0; i < 6; i++) args->scalarOutput[1 + i] = a[i];
        return ok ? kIOReturnSuccess : kIOReturnTimeout;
    }
    case 4: {   // ecRead(addr) -> val, -1 表示失败
        if (args->scalarInputCount < 1 || args->scalarOutputCount < 1) return kIOReturnBadArgument;
        uint8_t v = 0;
        bool ok = fDriver->ecRead((uint16_t)args->scalarInput[0], &v);
        args->scalarOutput[0] = ok ? (uint64_t)v : (uint64_t)-1;
        return ok ? kIOReturnSuccess : kIOReturnNotReady;
    }
    case 5: {   // ecWrite(addr, val) —— 需要先 arm
        if (args->scalarInputCount < 2) return kIOReturnBadArgument;
        bool ok = fDriver->ecWrite((uint16_t)args->scalarInput[0], (uint8_t)args->scalarInput[1]);
        return ok ? kIOReturnSuccess : kIOReturnNotPermitted;
    }
    case 6: {   // arm(magic) —— magic 必须是 0xECEC
        if (args->scalarInputCount < 1 || args->scalarInput[0] != 0xECEC) return kIOReturnNotPermitted;
        fDriver->ecArm(120);
        return kIOReturnSuccess;
    }
    case 7: {   // ecInfo -> [inuFound, canRead, canWrite, 0]
        if (args->scalarOutputCount < 3) return kIOReturnBadArgument;
        bool found = fDriver->ensureEc();
        args->scalarOutput[0] = found ? 1 : 0;
        uint8_t v = 0;
        args->scalarOutput[1] = (found && fDriver->ecRead(0x0000, &v)) ? 1 : 0;
        args->scalarOutput[2] = 0;
        return kIOReturnSuccess;
    }
    default:
        return kIOReturnUnsupported;
    }
}
