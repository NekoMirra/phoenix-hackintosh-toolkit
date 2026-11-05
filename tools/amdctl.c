// amdctl —— 通过 AMDProbe.kext 暴露的 SMN/SMU 通道控制 Phoenix(8845H)
// 用法:
//   amdctl info                     查看 CPU 型号、SMU 是否在线
//   amdctl smn <addr>               读 SMN 寄存器 (十六进制地址)
//   amdctl smnw <addr> <val>        写 SMN 寄存器
//   amdctl smu <msg> [a0..a5]       发 SMU 消息，打印应答与参数
//   amdctl ppt <mW>                 设 STAPM/PPT 上限（毫瓦，如 25000）
//   amdctl tctl <℃>                 设温度上限（摄氏度，如 75）
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <IOKit/IOKitLib.h>

#define SEL_INFO   0
#define SEL_SMN_R  1
#define SEL_SMN_W  2
#define SEL_SMU    3

static io_connect_t conn = 0;

static int openDrv(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AMDProbe"));
    if (!svc) { fprintf(stderr, "找不到 AMDProbe 驱动（kext 未加载？）\n"); return -1; }
    if (IOServiceOpen(svc, mach_task_self(), 0, &conn) != kIOReturnSuccess) {
        fprintf(stderr, "打不开 AMDProbe 用户客户端\n"); return -2;
    }
    return 0;
}

static uint32_t doSmu(uint32_t msg, uint32_t a[6], int quiet);

static int doInfo(void) {
    uint64_t out[8] = {0}; uint32_t cnt = 4;
    kern_return_t r = IOConnectCallScalarMethod(conn, SEL_INFO, NULL, 0, out, &cnt);
    if (r != kIOReturnSuccess) { printf("info 失败 0x%x\n", r); return -1; }
    printf("CPU family : 0x%llx\n", out[0]);
    printf("CPU model  : 0x%llx\n", out[1]);
    // 现场发一条 TestMessage，确认 SMU 固件是否应答
    uint32_t a[6] = {0};
    printf("SMU 测试   : ");
    fflush(stdout);
    uint32_t rep = doSmu(0x01, a, 1);
    if (rep == 0x01)      printf("应答正常 (0x01)，SMU 通道可用\n");
    else if (rep == 0)    printf("超时无应答 —— SMU 通道不通\n");
    else                  printf("应答 0x%02X\n", rep);
    return 0;
}

static int doSmnRead(uint32_t addr) {
    uint64_t in[1] = { addr }, out[4] = {0}; uint32_t cnt = 1;
    kern_return_t r = IOConnectCallScalarMethod(conn, SEL_SMN_R, in, 1, out, &cnt);
    if (r != kIOReturnSuccess) { printf("读失败 0x%x\n", r); return -1; }
    printf("SMN[0x%08X] = 0x%08llx\n", addr, out[0]);
    return 0;
}

static int doSmnWrite(uint32_t addr, uint32_t val) {
    uint64_t in[2] = { addr, val };
    kern_return_t r = IOConnectCallScalarMethod(conn, SEL_SMN_W, in, 2, NULL, NULL);
    printf("SMN[0x%08X] <- 0x%08X  (%s)\n", addr, val, r == kIOReturnSuccess ? "ok" : "fail");
    return r == kIOReturnSuccess ? 0 : -1;
}

static uint32_t doSmu(uint32_t msg, uint32_t a[6], int quiet) {
    uint64_t in[7] = { msg, a[0], a[1], a[2], a[3], a[4], a[5] };
    uint64_t out[7] = {0}; uint32_t cnt = 7;
    kern_return_t r = IOConnectCallScalarMethod(conn, SEL_SMU, in, 7, out, &cnt);
    if (r != kIOReturnSuccess && r != kIOReturnTimeout) {
        printf("SMU 调用失败 0x%x\n", r);
        return 0;
    }
    for (int i = 0; i < 6; i++) a[i] = (uint32_t)out[1 + i];
    if (!quiet) {
        printf("SMU msg 0x%02X -> 应答 0x%02llx  参数: %08x %08x %08x %08x %08x %08x\n",
               msg, out[0], a[0], a[1], a[2], a[3], a[4], a[5]);
        if (out[0] == 0)          printf("  (超时：固件无响应，消息 ID 可能不支持)\n");
        else if (out[0] == 0x01)  printf("  (成功)\n");
        else if (out[0] == 0xFE)  printf("  (未知命令)\n");
        else if (out[0] == 0xFD)  printf("  (前置条件拒绝)\n");
        else if (out[0] == 0xFC)  printf("  (忙)\n");
        else if (out[0] == 0xFF)  printf("  (失败)\n");
    }
    return (uint32_t)out[0];
}

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("用法: %s {info|smn <addr>|smnw <addr> <val>|smu <msg> [a0..a5]|ppt <mW>|tctl <C>}\n", argv[0]);
        return 1;
    }
    if (openDrv() != 0) return 1;

    const char *cmd = argv[1];
    int ret = 0;

    if (!strcmp(cmd, "info")) {
        ret = doInfo();
    } else if (!strcmp(cmd, "smn") && argc >= 3) {
        ret = doSmnRead((uint32_t)strtoul(argv[2], NULL, 16));
    } else if (!strcmp(cmd, "smnw") && argc >= 4) {
        ret = doSmnWrite((uint32_t)strtoul(argv[2], NULL, 16),
                         (uint32_t)strtoul(argv[3], NULL, 16));
    } else if (!strcmp(cmd, "smu") && argc >= 3) {
        uint32_t a[6] = {0};
        for (int i = 0; i < 6 && 3 + i < argc; i++) a[i] = (uint32_t)strtoul(argv[3 + i], NULL, 0);
        doSmu((uint32_t)strtoul(argv[2], NULL, 0), a, 0);
    } else if (!strcmp(cmd, "ppt") && argc >= 3) {
        uint32_t mw = (uint32_t)strtoul(argv[2], NULL, 0);
        printf("设置 STAPM / PPT-fast / PPT-slow = %u mW\n", mw);
        uint32_t a[6];
        uint32_t ids[3] = { 0x14, 0x15, 0x16 };
        const char *names[3] = { "STAPM", "PPT-fast", "PPT-slow" };
        for (int i = 0; i < 3; i++) {
            memset(a, 0, sizeof(a)); a[0] = mw;
            printf("  %-9s ", names[i]);
            doSmu(ids[i], a, 0);
        }
    } else if (!strcmp(cmd, "tctl") && argc >= 3) {
        uint32_t c = (uint32_t)strtoul(argv[2], NULL, 0);
        printf("设置 Tctl 温度上限 = %u ℃\n", c);
        uint32_t a[6] = { c, 0, 0, 0, 0, 0 };
        doSmu(0x19, a, 0);
    } else {
        printf("未知命令\n"); ret = 1;
    }

    IOServiceClose(conn);
    return ret;
}
