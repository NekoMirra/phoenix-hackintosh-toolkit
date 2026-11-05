// checkhost.c — 用与 kext 完全相同的判断逻辑，在用户态验证能否找到 AMD 主机桥
// 目的：避免改完还要靠重启才知道匹配对不对
#include <stdio.h>
#include <IOKit/IOKitLib.h>

static int isAmdHostBridge(io_registry_entry_t svc, char *why, size_t n) {
    int ok = 0;
    CFTypeRef v = IORegistryEntryCreateCFProperty(svc, CFSTR("vendor-id"),
                                                  kCFAllocatorDefault, 0);
    unsigned int vid = 0;
    if (v && CFGetTypeID(v) == CFDataGetTypeID() && CFDataGetLength((CFDataRef)v) >= 4) {
        vid = *(const unsigned int *)CFDataGetBytePtr((CFDataRef)v);
        ok = (vid == 0x1022);
    }
    if (v) CFRelease(v);
    if (!ok) { snprintf(why, n, "vendor=0x%x", vid); return 0; }

    CFTypeRef c = IORegistryEntryCreateCFProperty(svc, CFSTR("class-code"),
                                                  kCFAllocatorDefault, 0);
    int hit = 0;
    if (c && CFGetTypeID(c) == CFDataGetTypeID() && CFDataGetLength((CFDataRef)c) >= 3) {
        const unsigned char *b = (const unsigned char *)CFDataGetBytePtr((CFDataRef)c);
        // [progIF, subClass, baseClass]
        hit = (b[2] == 0x06 && b[1] == 0x00);
        snprintf(why, n, "class=%02x/%02x", b[2], b[1]);
    } else {
        snprintf(why, n, "class-code 缺失/过短");
    }
    if (c) CFRelease(c);
    return hit;
}

int main(void) {
    CFMutableDictionaryRef m = IOServiceMatching("IOPCIDevice");
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, m, &it) != KERN_SUCCESS) {
        printf("枚举失败\n"); return 1;
    }
    io_object_t o;
    int total = 0, round1 = -1, round2 = -1, idx = 0;
    while ((o = IOIteratorNext(it))) {
        total++;
        char why[64] = {0};
        int host = isAmdHostBridge(o, why, sizeof(why));

        char pdbg[32] = {0};
        CFTypeRef p = IORegistryEntryCreateCFProperty(o, CFSTR("pcidebug"),
                                                      kCFAllocatorDefault, 0);
        if (p && CFGetTypeID(p) == CFStringGetTypeID())
            CFStringGetCString((CFStringRef)p, pdbg, sizeof(pdbg), kCFStringEncodingUTF8);
        if (p) CFRelease(p);

        int bus0dev0 = (pdbg[0]=='0' && pdbg[1]==':' && pdbg[2]=='0' && pdbg[3]==':' && pdbg[4]=='0');

        if (host || bus0dev0)
            printf("  [%d] pcidebug=%-8s %-18s host=%d bus0dev0=%d\n",
                   idx, pdbg, why, host, bus0dev0);

        if (host && bus0dev0 && round1 < 0) round1 = idx;
        if (host && round2 < 0) round2 = idx;
        idx++;
        IOObjectRelease(o);
    }
    IOObjectRelease(it);

    printf("\n共 %d 个 IOPCIDevice\n", total);
    printf("第一轮(host && 0:0:0) 命中 index = %d %s\n", round1, round1 >= 0 ? "OK" : "失败");
    printf("第二轮(host)          命中 index = %d %s\n", round2, round2 >= 0 ? "OK" : "失败");
    return (round2 >= 0) ? 0 : 1;
}
