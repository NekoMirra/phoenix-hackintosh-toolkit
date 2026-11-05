// ntfslog.c — 读取 NTFS $LogFile 的 restart page（LSN 0）
// 用法：ntfslog show <device>   /   ntfslog cleardirty <device>
//
// restart page header 布局（小端）：
//   0x00 signature "RSTR"
//   0x04 usa offset (u16)
//   0x06 usa count  (u16)
//   0x08 major ver  (u16)
//   0x0A minor ver  (u16)
//   0x0C system page (u16)
//   0x0E log page size (u16)
//   0x10 restart offset (u64)
//   0x18 flags (u32)   bit0 = 卷脏（VOLUME_DIRTY）

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <errno.h>

static uint16_t rd16(const uint8_t *p) { return (uint16_t)p[0] | ((uint16_t)p[1] << 8); }
static uint32_t rd32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static uint64_t rd64(const uint8_t *p) {
    uint64_t v = 0; for (int i = 7; i >= 0; i--) v = (v << 8) | p[i]; return v;
}

// 解析 runlist，返回第一个 run 的 LCN；找不到返回 -1
static long long first_lcn(const uint8_t *rl, size_t maxlen) {
    size_t i = 0;
    while (i < maxlen) {
        uint8_t hdr = rl[i++];
        if (hdr == 0) break;
        int len_bytes = hdr & 0x0F;
        int off_bytes = (hdr >> 4) & 0x0F;
        if (!len_bytes || !off_bytes) break;
        if (i + len_bytes + off_bytes > maxlen) break;
        i += len_bytes;                       // 跳过长度字段
        int64_t off = 0;
        for (int b = off_bytes - 1; b >= 0; b--) off = (off << 8) | rl[i + b];
        return off;                           // 第一个 run 用绝对 LCN
    }
    return -1;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: ntfslog show|cleardirty <device>\n"); return 2; }
    int do_clear = !strcmp(argv[1], "cleardirty");
    const char *dev = argv[2];

    int fd = open(dev, O_RDONLY);
    if (fd < 0) { fprintf(stderr, "open: %s\n", strerror(errno)); return 1; }

    uint8_t bs[512];
    if (pread(fd, bs, 512, 0) != 512) { fprintf(stderr, "读引导扇区失败\n"); return 1; }
    uint32_t bps = rd16(bs + 0x0B), spc = bs[0x0D];
    uint64_t mft = rd64(bs + 0x30);
    int8_t cpr = (int8_t)bs[0x40];
    uint64_t cluster = (uint64_t)bps * spc;
    uint32_t recsize = (cpr > 0) ? (uint32_t)cpr * bps : (uint32_t)(1u << (-cpr));
    uint64_t logrec_off = mft * cluster + 2ULL * recsize;   // 记录 2 = $LogFile

    uint8_t *rec = malloc(recsize);
    if (pread(fd, rec, recsize, logrec_off) != (ssize_t)recsize) { fprintf(stderr, "读记录2失败\n"); return 1; }
    if (memcmp(rec, "FILE", 4) != 0) { fprintf(stderr, "记录2签名异常\n"); return 1; }

    uint16_t aoff = rd16(rec + 0x14);
    long long lcn = -1;
    for (uint32_t o = aoff; o + 16 < recsize; ) {
        uint32_t type = rd32(rec + o), len = rd32(rec + o + 4);
        if (type == 0xFFFFFFFF || len < 16) break;
        if (type == 0x80 && rec[o + 8] == 1) {         // $DATA 非驻留
            uint16_t rl_off = rd16(rec + o + 0x20);
            lcn = first_lcn(rec + o + rl_off, recsize - (o + rl_off));
            break;
        }
        o += len;
    }
    if (lcn < 0) { fprintf(stderr, "未找到 $LogFile 的 $DATA run\n"); free(rec); return 1; }

    uint64_t page_off = (uint64_t)lcn * cluster;
    uint8_t page[4096];
    if (pread(fd, page, sizeof(page), page_off) != (ssize_t)sizeof(page)) { fprintf(stderr, "读日志页失败\n"); return 1; }

    printf("设备        : %s\n", dev);
    printf("$LogFile LCN: %lld (偏移 %llu)\n", lcn, (unsigned long long)page_off);
    printf("签名        : %.4s\n", page);
    if (memcmp(page, "RSTR", 4) != 0) {
        printf("不是 RSTR 页，原始前 32 字节:\n");
        for (int i = 0; i < 32; i++) printf("%02X ", page[i]);
        printf("\n"); free(rec); close(fd); return 1;
    }
    uint32_t flags = rd32(page + 0x18);
    printf("日志版本    : %u.%u\n", rd16(page + 0x08), rd16(page + 0x0A));
    printf("flags       : 0x%08X  (bit0 卷脏=%d)\n", flags, flags & 1);

    if (do_clear && (flags & 1)) {
        uint32_t nf = flags & ~1u;
        int wfd = open(dev, O_WRONLY);
        if (wfd < 0) { fprintf(stderr, "写打开失败: %s\n", strerror(errno)); return 1; }
        if (pwrite(wfd, &nf, 4, page_off + 0x18) != 4) { fprintf(stderr, "写入失败: %s\n", strerror(errno)); return 1; }
        fsync(wfd); close(wfd);
        uint8_t chk[4];
        pread(fd, chk, 4, page_off + 0x18);
        printf("写入后 flags: 0x%08X -> %s\n", rd32(chk), (rd32(chk) & 1) ? "仍脏" : "已清除 ✅");
    }
    free(rec); close(fd);
    return 0;
}
