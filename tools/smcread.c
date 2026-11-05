// smcread - 直接读 AppleSMC 全部传感器键（温度/风扇/电压/电流）
// 用于黑苹果上读取 SMCAMDProcessor / VirtualSMC 发布的传感器数据
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <IOKit/IOKitLib.h>

typedef int16_t Int16;

#define KERNEL_INDEX_SMC      2
#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_READ_INDEX    8
#define SMC_CMD_READ_KEYINFO  9

typedef struct { char major, minor, build, reserved[1]; UInt16 release; } SMCVers;
typedef struct { UInt16 version, length; UInt32 cpuPLimit, gpuPLimit, memPLimit; } SMCPLimit;
typedef struct { UInt32 dataSize, dataType; char dataAttributes; } SMCKeyInfo;

typedef struct {
    UInt32 key;
    SMCVers vers;
    SMCPLimit pLimitData;
    SMCKeyInfo keyInfo;
    char result, status, data8;
    UInt32 data32;
    UInt8 bytes[32];
} SMCKeyData;

static io_connect_t conn = 0;

static kern_return_t SMCCall(int index, SMCKeyData *in, SMCKeyData *out) {
    size_t outSize = sizeof(SMCKeyData);
    return IOConnectCallStructMethod(conn, index, in, sizeof(SMCKeyData), out, &outSize);
}

static UInt32 FOURCC(const char *s) {
    return ((UInt32)(UInt8)s[0] << 24) | ((UInt32)(UInt8)s[1] << 16) |
           ((UInt32)(UInt8)s[2] << 8) | (UInt32)(UInt8)s[3];
}

static int readKeyInfo(UInt32 key, SMCKeyInfo *ki) {
    SMCKeyData in, out;
    memset(&in, 0, sizeof(in)); memset(&out, 0, sizeof(out));
    in.key = key;
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (SMCCall(KERNEL_INDEX_SMC, &in, &out) != kIOReturnSuccess) return -1;
    if (out.result != 0) return -2;
    *ki = out.keyInfo;
    return 0;
}

static int readBytes(UInt32 key, UInt8 *buf, UInt32 *size) {
    SMCKeyInfo ki;
    if (readKeyInfo(key, &ki) != 0) return -1;
    SMCKeyData in, out;
    memset(&in, 0, sizeof(in)); memset(&out, 0, sizeof(out));
    in.key = key;
    in.keyInfo.dataSize = ki.dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    if (SMCCall(KERNEL_INDEX_SMC, &in, &out) != kIOReturnSuccess) return -2;
    if (out.result != 0) return -3;
    UInt32 n = ki.dataSize > 32 ? 32 : ki.dataSize;
    memcpy(buf, out.bytes, n);
    *size = n;
    return 0;
}

static int keyCount(int *count) {
    UInt8 b[32]; UInt32 n;
    SMCKeyInfo ki;
    int r1 = readKeyInfo(FOURCC("#KEY"), &ki);
    fprintf(stderr, "[debug] #KEY keyInfo ret=%d dataSize=%u type=0x%08x\n", r1, ki.dataSize, ki.dataType);
    int r = readBytes(FOURCC("#KEY"), b, &n);
    fprintf(stderr, "[debug] #KEY readBytes ret=%d n=%u bytes=%02x %02x\n", r, n, b[0], b[1]);
    if (r != 0) return -1;
    *count = n >= 2 ? (b[0] << 8 | b[1]) : 0;
    return 0;
}

static void fmt(const char *type, const UInt8 *b, UInt32 n, char *out, size_t osz) {
    out[0] = 0;
    if (!strcmp(type, "sp78") && n >= 2) {
        int v = (int)((Int16)((b[0] << 8) | b[1]));
        snprintf(out, osz, "%.2f", v / 256.0);
    } else if (!strcmp(type, "fpe2") && n >= 2) {
        snprintf(out, osz, "%.1f", ((b[0] << 8) | b[1]) / 4.0);
    } else if (!strcmp(type, "flt ") && n >= 4) {
        UInt32 raw = (UInt32)b[0] << 24 | (UInt32)b[1] << 16 | (UInt32)b[2] << 8 | b[3];
        float f; memcpy(&f, &raw, 4);
        if (f > -1000 && f < 100000) snprintf(out, osz, "%.2f", f);
        else { raw = (UInt32)b[3] << 24 | (UInt32)b[2] << 16 | (UInt32)b[1] << 8 | b[0];
               memcpy(&f, &raw, 4); snprintf(out, osz, "%.2f(rev)", f); }
    } else if (!strcmp(type, "ui16") && n >= 2) {
        snprintf(out, osz, "%u", (unsigned)((b[0] << 8) | b[1]));
    } else if (!strcmp(type, "ui8 ") && n >= 1) {
        snprintf(out, osz, "%u", (unsigned)b[0]);
    } else if (!strcmp(type, "si16") && n >= 2) {
        snprintf(out, osz, "%d", (int)(Int16)((b[0] << 8) | b[1]));
    } else {
        int p = 0;
        for (UInt32 i = 0; i < n && p < (int)osz - 3; i++) p += snprintf(out + p, osz - p, "%02x", b[i]);
    }
}

static int dumpKey(const char *ks) {
    UInt8 b[32]; UInt32 sz = 0;
    if (strlen(ks) != 4) return 0;
    if (readBytes(FOURCC(ks), b, &sz) != 0) return 0;
    SMCKeyInfo ki;
    if (readKeyInfo(FOURCC(ks), &ki) != 0) return 0;
    char t[5];
    t[0] = (ki.dataType >> 24) & 0xff; t[1] = (ki.dataType >> 16) & 0xff;
    t[2] = (ki.dataType >> 8) & 0xff;  t[3] = ki.dataType & 0xff; t[4] = 0;
    for (int j = 0; t[j]; j++) if (t[j] < 32 || t[j] > 126) t[j] = '?';
    char v[128];
    fmt(t, b, sz, v, sizeof(v));
    printf("  %-4s  [%s] size=%u  = %s\n", ks, t, ki.dataSize, v);
    return 1;
}

int main(int argc, char **argv) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) { fprintf(stderr, "找不到 AppleSMC（VirtualSMC 未加载？）\n"); return 1; }
    if (IOServiceOpen(svc, mach_task_self(), 0, &conn) != kIOReturnSuccess) {
        fprintf(stderr, "打不开 AppleSMC user client\n"); return 2;
    }

    // 显式指定键名
    if (argc > 1 && strlen(argv[1]) == 4) {
        int ok = 0;
        for (int i = 1; i < argc; i++) ok += dumpKey(argv[i]);
        if (!ok) printf("  指定的键都不存在\n");
        IOServiceClose(conn);
        return 0;
    }

    // 候选键扫描
    static const char *cand[] = {
        // CPU 温度
        "TC0P","TC0D","TC0E","TC0F","TC0H","TC0J","TC1C","TC2C","TC3C","TC4C",
        "Tp01","Tp05","Tp09","Tp0D","Tp0H","Tp0L","Tp0P","Tp0T","Tp0X",
        // GPU / 主板
        "TG0P","TG0D","TG0E","TB0T","Ts0P","TN0P","TH0P","Tm0P",
        // 风扇
        "F0Ac","F0Mn","F0Mx","F0Tg","F0ID","F0Sf","F1Ac",
        // 电源/电流/电压
        "PCPT","PCPR","PCPC","PC0R","PDTR","PSTR","PPBR","PSTR",
        "VC0C","IC0C","PC0C","PS0C",
        NULL
    };
    int shown = 0;
    printf("=== CPU 温度 ===\n");
    for (int i = 0; i < 20; i++) if (cand[i]) shown += dumpKey(cand[i]);
    printf("=== GPU/主板 ===\n");
    for (int i = 20; i < 34; i++) if (cand[i]) shown += dumpKey(cand[i]);
    printf("=== 风扇 ===\n");
    for (int i = 34; i < 41; i++) if (cand[i]) shown += dumpKey(cand[i]);
    printf("=== 功耗/电压 ===\n");
    for (int i = 41; cand[i]; i++) shown += dumpKey(cand[i]);
    printf("\n共命中 %d 个键\n", shown);
    IOServiceClose(conn);
    return 0;
}
