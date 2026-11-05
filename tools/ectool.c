// ectool —— 通过 AMDProbe.kext 的 EC 通道读写笔记本 EC（同方/机械革命模具 INOU.ECRR/ECRW）
// 用法:
//   ectool info                     探测 INOU 设备与 EC 读通道是否可用
//   ectool read <addr>              读一个 EC 字节 (十六进制地址，如 0x751)
//   ectool readw <addr>             读 16 位小端字
//   ectool scan [start] [end]       扫描并打印非零/可疑寄存器（默认 0x000-0xFFF）
//   ectool watch <addr>[,<addr>...] 连续采样，观察变化（默认 10 秒）
//   ectool write <addr> <val>       写 EC（必须先 --i-understand，最多 32 次/次解锁）
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <IOKit/IOKitLib.h>

#define SEL_INFO  0
#define SEL_EC_R  4
#define SEL_EC_W  5
#define SEL_ARM   6
#define SEL_ECINFO 7

static io_connect_t conn = 0;

static int openDrv(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AMDProbe"));
    if (!svc) { fprintf(stderr, "找不到 AMDProbe 驱动（kext 未加载？）\n"); return -1; }
    if (IOServiceOpen(svc, mach_task_self(), 0, &conn) != kIOReturnSuccess) {
        fprintf(stderr, "打不开 AMDProbe 用户客户端\n"); return -2;
    }
    return 0;
}

static int ecRead(uint32_t addr, uint8_t *out) {
    uint64_t in[1] = { addr }, o[1] = {0}; uint32_t cnt = 1;
    kern_return_t r = IOConnectCallScalarMethod(conn, SEL_EC_R, in, 1, o, &cnt);
    if (r != kIOReturnSuccess) return -1;
    *out = (uint8_t)o[0];
    return 0;
}

static int ecWrite(uint32_t addr, uint8_t val) {
    uint64_t in[2] = { addr, val };
    kern_return_t r = IOConnectCallScalarMethod(conn, SEL_EC_W, in, 2, NULL, NULL);
    return r == kIOReturnSuccess ? 0 : -1;
}

static void doInfo(void) {
    uint64_t out[4] = {0}; uint32_t cnt = 3;
    kern_return_t r = IOConnectCallScalarMethod(conn, SEL_ECINFO, NULL, 0, out, &cnt);
    if (r != kIOReturnSuccess) { printf("EC 探测失败 0x%x\n", r); return; }
    printf("INOU 设备   : %s\n", out[0] ? "找到" : "未找到");
    printf("EC 读通道   : %s\n", out[1] ? "可用" : "不可用");
    uint8_t v;
    if (ecRead(0x751, &v) == 0) printf("EC[0x751]   : 0x%02X  (性能/风扇模式寄存器)\n", v);
}

static void doScan(uint32_t start, uint32_t end) {
    printf("扫描 EC 0x%03X - 0x%03X ...\n", start, end);
    int n = 0;
    for (uint32_t a = start; a <= end; a++) {
        uint8_t v;
        if (ecRead(a, &v) != 0) { printf("读 0x%03X 失败，中止\n", a); return; }
        if (v != 0 && v != 0xFF) { printf("  0x%03X = 0x%02X (%3u)\n", a, v, v); n++; }
        if ((a & 0xFF) == 0xFF) fflush(stdout);
    }
    printf("共 %d 个非零寄存器\n", n);
}

static void doWatch(const char *list, int seconds) {
    uint32_t addrs[16]; int n = 0;
    char buf[256]; strncpy(buf, list, sizeof(buf) - 1); buf[sizeof(buf) - 1] = 0;
    for (char *t = strtok(buf, ","); t && n < 16; t = strtok(NULL, ","))
        addrs[n++] = (uint32_t)strtoul(t, NULL, 0);
    printf("采样 %d 个寄存器，%d 秒...\n", n, seconds);
    for (int s = 0; s < seconds; s++) {
        printf("t=%02ds ", s);
        for (int i = 0; i < n; i++) {
            uint8_t v;
            if (ecRead(addrs[i], &v) == 0) printf("[0x%03X]=0x%02X ", addrs[i], v);
            else printf("[0x%03X]=ERR ", addrs[i]);
        }
        printf("\n"); fflush(stdout);
        sleep(1);
    }
}

static void doDump(const char *path, uint32_t start, uint32_t end) {
    FILE *f = fopen(path, "wb");
    if (!f) { printf("无法写入 %s\n", path); return; }
    printf("转储 EC 0x%03X - 0x%03X -> %s ...\n", start, end, path);
    for (uint32_t a = start; a <= end; a++) {
        uint8_t v;
        if (ecRead(a, &v) != 0) { printf("\n读 0x%03X 失败，中止\n", a); fclose(f); return; }
        fputc(v, f);
    }
    fclose(f);
    printf("完成，共 %u 字节\n", end - start + 1);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("用法: %s {info|read <addr>|readw <addr>|scan [start] [end]|watch <a,b,..> [sec]|write <addr> <val> --i-understand}\n", argv[0]);
        return 1;
    }
    if (openDrv() != 0) return 1;

    if (!strcmp(argv[1], "info")) {
        doInfo();
    } else if (!strcmp(argv[1], "read") && argc >= 3) {
        uint8_t v;
        if (ecRead((uint32_t)strtoul(argv[2], NULL, 0), &v) == 0)
            printf("EC[0x%03X] = 0x%02X (%u)\n", (uint32_t)strtoul(argv[2], NULL, 0), v, v);
        else printf("读失败\n");
    } else if (!strcmp(argv[1], "readw") && argc >= 3) {
        uint32_t a = (uint32_t)strtoul(argv[2], NULL, 0);
        uint8_t lo, hi;
        if (ecRead(a, &lo) == 0 && ecRead(a + 1, &hi) == 0)
            printf("EC[0x%03X..] = 0x%04X (%u)\n", a, lo | (hi << 8), lo | (hi << 8));
        else printf("读失败\n");
    } else if (!strcmp(argv[1], "scan")) {
        uint32_t s = argc >= 3 ? (uint32_t)strtoul(argv[2], NULL, 0) : 0x000;
        uint32_t e = argc >= 4 ? (uint32_t)strtoul(argv[3], NULL, 0) : 0xFFF;
        doScan(s, e);
    } else if (!strcmp(argv[1], "dump") && argc >= 3) {
        uint32_t s = argc >= 4 ? (uint32_t)strtoul(argv[3], NULL, 0) : 0x000;
        uint32_t e = argc >= 5 ? (uint32_t)strtoul(argv[4], NULL, 0) : 0xFFF;
        doDump(argv[2], s, e);
    } else if (!strcmp(argv[1], "watch") && argc >= 3) {
        doWatch(argv[2], argc >= 4 ? atoi(argv[3]) : 10);
    } else if (!strcmp(argv[1], "write") && argc >= 5) {
        int ok = 0;
        for (int i = 4; i < argc; i++) if (!strcmp(argv[i], "--i-understand")) ok = 1;
        if (!ok) { printf("写 EC 需要显式加 --i-understand\n"); return 1; }
        uint64_t in[1] = { 0xECEC };
        if (IOConnectCallScalarMethod(conn, SEL_ARM, in, 1, NULL, NULL) != kIOReturnSuccess) {
            printf("解锁失败\n"); return 1;
        }
        uint32_t a = (uint32_t)strtoul(argv[2], NULL, 0);
        uint8_t oldv = 0, newv = (uint8_t)strtoul(argv[3], NULL, 0);
        ecRead(a, &oldv);
        printf("EC[0x%03X]: 0x%02X -> 0x%02X ... ", a, oldv, newv);
        fflush(stdout);
        if (ecWrite(a, newv) == 0) {
            uint8_t back = 0;
            ecRead(a, &back);
            printf("%s (读回 0x%02X)\n", back == newv ? "成功" : "写后读回不一致", back);
        } else printf("失败\n");
    } else {
        printf("未知命令\n"); return 1;
    }
    return 0;
}
