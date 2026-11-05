// cfgprobe.c — 纯用户态探测：能否通过 IOPCIDevice user client 访问 PCI 配置空间
// 若能，则 SMN 窗口(0xB8/0xBC)可不依赖任何 kext 直接访问
#include <stdio.h>
#include <IOKit/IOKitLib.h>

int main(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault,
                                                   IOServiceMatching("IOPCIDevice"));
    if (!svc) { printf("没找到 IOPCIDevice 节点\n"); return 1; }
    printf("找到 IOPCIDevice: 0x%x\n", svc);

    // 打印该设备关键属性，确认是不是主机桥
    CFTypeRef v = IORegistryEntryCreateCFProperty(svc, CFSTR("vendor-id"),
                                                  kCFAllocatorDefault, 0);
    if (v) {
        unsigned int vid = *(const unsigned int *)CFDataGetBytePtr((CFDataRef)v);
        printf("vendor-id: 0x%x\n", vid);
        CFRelease(v);
    }

    io_connect_t conn = 0;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    printf("IOServiceOpen rc=0x%x %s\n", kr,
           kr == kIOReturnSuccess ? "OK" : "失败");
    if (kr != kIOReturnSuccess) {
        IOObjectRelease(svc);
        return 1;
    }

    // 枚举 selector 0..12，看哪些能返回数据
    for (uint32_t sel = 0; sel <= 12; sel++) {
        uint64_t in[2] = {0x00, 0};   // offset 0
        uint64_t out[4] = {0};
        uint32_t outCnt = 4;
        kr = IOConnectCallScalarMethod(conn, sel, in, 1, out, &outCnt);
        if (kr == kIOReturnSuccess)
            printf("  sel=%2u OK  outCnt=%u  val=0x%llx\n", sel, outCnt,
                   (unsigned long long)out[0]);
        else
            printf("  sel=%2u rc=0x%x\n", sel, kr);
    }

    // 重点测 0xB8(索引) / 0xBC(数据)：先读原值
    printf("\n--- 直接读 0xB8 / 0xBC ---\n");
    for (uint32_t off = 0xB8; off <= 0xBC; off += 4) {
        uint64_t in[2] = {off, 0};
        uint64_t out[4] = {0};
        uint32_t outCnt = 4;
        kr = IOConnectCallScalarMethod(conn, 2, in, 1, out, &outCnt);  // 假设 sel2=Read32
        printf("  offset 0x%02X: rc=0x%x val=0x%llx\n", off, kr,
               (unsigned long long)out[0]);
    }

    IOServiceClose(conn);
    IOObjectRelease(svc);
    return 0;
}
