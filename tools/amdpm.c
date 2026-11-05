// amdpm - 控制 AMDRyzenCPUPowerManagement 的用户态工具
// 通过 IOKit user client (AMDRyzenCPUPMUserClient) 调用内核侧选择器
// selector 11: 读 CPB 支持/状态   selector 12: 设置 CPB
// selector 13: 读 P-state 上限>=1  selector 14: 设上限 0/1
// selector 18: 读上限==2          selector 19: 设上限 2/1

#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static io_connect_t gConn = 0;

static int openConn(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault,
                                                   IOServiceMatching("AMDRyzenCPUPowerManagement"));
    if (!svc) {
        fprintf(stderr, "找不到 AMDRyzenCPUPowerManagement 服务（驱动未加载？）\n");
        return -1;
    }
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &gConn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "IOServiceOpen 失败: 0x%x —— 需要 root 权限\n", kr);
        return -1;
    }
    return 0;
}

static kern_return_t invoke(uint32_t sel, uint64_t inVal, int hasIn,
                            uint64_t *out, uint32_t *outCnt,
                            void *outStruct, size_t *outStructCnt) {
    uint64_t scalarIn[1];
    scalarIn[0] = inVal;
    return IOConnectCallMethod(gConn, sel,
                               hasIn ? scalarIn : NULL, hasIn ? 1 : 0,
                               NULL, 0,
                               out, outCnt,
                               outStruct, outStructCnt);
}

// 返回 P-state 上限：0 / 1 / 2
static int getLimit(void) {
    uint64_t out[4] = {0};
    uint32_t outCnt = 4;
    unsigned char sbuf[64] = {0};
    size_t scnt = sizeof(sbuf);

    if (invoke(18, 0, 0, out, &outCnt, sbuf, &scnt) == KERN_SUCCESS) {
        uint64_t v = *(uint64_t *)sbuf;
        if (v == 1) return 2;
    }
    memset(sbuf, 0, sizeof(sbuf));
    scnt = sizeof(sbuf);
    outCnt = 4;
    if (invoke(13, 0, 0, out, &outCnt, sbuf, &scnt) == KERN_SUCCESS) {
        uint64_t v = *(uint64_t *)sbuf;
        if (v == 1) return 1;
    }
    return 0;
}

static int getCpb(int *supported) {
    uint64_t out[4] = {0};
    uint32_t outCnt = 4;
    unsigned char sbuf[64] = {0};
    size_t scnt = sizeof(sbuf);

    kern_return_t kr = invoke(11, 0, 0, out, &outCnt, sbuf, &scnt);
    if (kr != KERN_SUCCESS) return -1;
    uint64_t *p = (uint64_t *)sbuf;
    *supported = (int)p[0];
    return (int)p[1];
}

static void usage(void) {
    printf("用法: amdpm <命令>\n\n");
    printf("  status         查看当前状态\n");
    printf("  cpb on|off     开关 Core Performance Boost（超频上限）\n");
    printf("  limit 0|1|2    设置 P-state 上限（0=最高性能 2=允许最低档）\n\n");
    printf("说明: limit 0 只允许 P0；limit 1 允许降到 P1(=P0 的 80%%)；limit 2 允许更低档\n");
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(); return 1; }
    if (openConn() != 0) return 1;

    const char *cmd = argv[1];

    if (!strcmp(cmd, "status")) {
        int sup = 0;
        int cpb = getCpb(&sup);
        int lim = getLimit();
        printf("CPB 支持: %s\n", sup ? "是" : "否");
        if (cpb >= 0) printf("CPB 状态: %s\n", cpb ? "开启（允许超频）" : "关闭（锁在基频）");
        printf("P-state 上限: P%d\n", lim);
    } else if (!strcmp(cmd, "cpb")) {
        if (argc < 3) { usage(); return 1; }
        int on = !strcmp(argv[2], "on") ? 1 : 0;
        kern_return_t kr = invoke(12, on, 1, NULL, NULL, NULL, NULL);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "设置 CPB 失败: 0x%x\n", kr);
            return 1;
        }
        printf("CPB 已%s\n", on ? "开启" : "关闭");
    } else if (!strcmp(cmd, "limit")) {
        if (argc < 3) { usage(); return 1; }
        int want = atoi(argv[2]);
        kern_return_t kr;
        if (want == 0) {
            kr = invoke(14, 0, 1, NULL, NULL, NULL, NULL);
        } else if (want == 1) {
            kr = invoke(19, 0, 1, NULL, NULL, NULL, NULL);   // 2 -> 1
            kr = invoke(14, 1, 1, NULL, NULL, NULL, NULL);   // -> 1
        } else if (want == 2) {
            kr = invoke(19, 1, 1, NULL, NULL, NULL, NULL);   // -> 2
        } else {
            fprintf(stderr, "limit 只能是 0/1/2\n");
            return 1;
        }
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "设置 P-state 上限失败: 0x%x\n", kr);
            return 1;
        }
        printf("P-state 上限已设为 P%d（生效值: P%d）\n", want, getLimit());
    } else {
        usage();
        return 1;
    }

    IOServiceClose(gConn);
    return 0;
}
