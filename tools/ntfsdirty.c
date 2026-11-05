// ntfsdirty.c — 读取/清除 NTFS $Volume 记录中的 dirty 标志位
//
// 用法：
//   ntfsdirty show  /dev/rdisk0s2
//   ntfsdirty clear /dev/rdisk0s2
//
// 原理：解析 NTFS 引导扇区 → 定位 $MFT → 读取记录 3（$Volume）
//       → 找到 $VOLUME_INFORMATION(0x70) 属性 → flags 字段（value+0x0A）
//       → dirty 位 = 0x0001
// 只对 flags 的 2 个字节做 pwrite，不重写整条记录（避免 USA 修正问题）。

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <errno.h>
#include <time.h>

static uint16_t rd16(const uint8_t *p) { return (uint16_t)p[0] | ((uint16_t)p[1] << 8); }
static uint32_t rd32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static uint64_t rd64(const uint8_t *p) {
    uint64_t v = 0;
    for (int i = 7; i >= 0; i--) v = (v << 8) | p[i];
    return v;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: ntfsdirty show|clear <device>\n");
        return 2;
    }
    int do_clear = !strcmp(argv[1], "clear");
    int do_set = !strcmp(argv[1], "set");
    uint16_t set_val = 0;
    if (do_set) {
        if (argc < 4) { fprintf(stderr, "usage: ntfsdirty set <device> <hexflags>\n"); return 2; }
        set_val = (uint16_t)strtoul(argv[3], NULL, 0);
    }
    const char *dev = argv[2];

    int fd = open(dev, O_RDONLY);
    if (fd < 0) { fprintf(stderr, "open %s: %s\n", dev, strerror(errno)); return 1; }

    uint8_t bs[512];
    if (pread(fd, bs, sizeof(bs), 0) != sizeof(bs)) {
        fprintf(stderr, "读引导扇区失败\n"); close(fd); return 1;
    }
    if (memcmp(bs + 3, "NTFS    ", 8) != 0) {
        fprintf(stderr, "不是 NTFS 卷（OEM=%.8s）\n", bs + 3); close(fd); return 1;
    }

    uint32_t bps  = rd16(bs + 0x0B);
    uint32_t spc  = bs[0x0D];
    uint64_t mft  = rd64(bs + 0x30);
    int8_t   cpr  = (int8_t)bs[0x40];

    if (bps == 0 || spc == 0) { fprintf(stderr, "簇参数异常\n"); close(fd); return 1; }
    uint64_t cluster = (uint64_t)bps * spc;
    uint32_t recsize = (cpr > 0) ? (uint32_t)cpr * bps : (uint32_t)(1u << (-cpr));
    uint64_t mft_off = mft * cluster;
    uint64_t rec_off = mft_off + 3ULL * recsize;

    printf("设备        : %s\n", dev);
    printf("扇区/簇     : %u / %u  -> 簇 %llu 字节\n", bps, spc, (unsigned long long)cluster);
    printf("MFT LCN     : %llu (偏移 %llu)\n", (unsigned long long)mft, (unsigned long long)mft_off);
    printf("MFT 记录大小: %u\n", recsize);
    printf("$Volume 记录: 偏移 %llu\n\n", (unsigned long long)rec_off);

    uint8_t *rec = malloc(recsize);
    if (!rec) { close(fd); return 1; }
    if (pread(fd, rec, recsize, rec_off) != (ssize_t)recsize) {
        fprintf(stderr, "读 $Volume 记录失败\n"); free(rec); close(fd); return 1;
    }
    if (memcmp(rec, "FILE", 4) != 0) {
        fprintf(stderr, "记录签名不是 FILE：%02X %02X %02X %02X（偏移可能算错，已中止）\n",
                rec[0], rec[1], rec[2], rec[3]);
        free(rec); close(fd); return 1;
    }

    uint16_t attr_off = rd16(rec + 0x14);
    printf("属性起始偏移: 0x%X\n", attr_off);
    int found = 0;
    uint64_t flag_off = 0;
    uint16_t flags = 0;

    for (uint32_t o = attr_off; o + 16 < recsize; ) {
        uint32_t type = rd32(rec + o);
        uint32_t len  = rd32(rec + o + 4);
        if (type == 0xFFFFFFFF || len == 0) break;
        if (len < 16 || o + len > recsize) {
            printf("属性长度异常（type=0x%X len=%u），停止解析\n", type, len);
            break;
        }
        if (type == 0x70) {   // $VOLUME_INFORMATION
            uint8_t nonres = rec[o + 8];
            if (nonres) { printf("$VOLUME_INFORMATION 非驻留，放弃\n"); break; }
            uint32_t vlen = rd32(rec + o + 0x10);
            uint16_t voff = rd16(rec + o + 0x14);
            if (vlen < 12) { printf("属性值过短（%u）\n", vlen); break; }
            flag_off = rec_off + o + voff + 10;
            flags = rd16(rec + o + voff + 10);
            found = 1;
            printf("$VOLUME_INFORMATION: 版本 %u.%u, flags=0x%04X\n",
                   rec[o + voff + 8], rec[o + voff + 9], flags);
            break;
        }
        o += len;
    }

    if (!found) { fprintf(stderr, "未找到 $VOLUME_INFORMATION，中止\n"); free(rec); close(fd); return 1; }

    printf("dirty 位(0x0001): %s\n", (flags & 1) ? "SET（脏）" : "已清除");

    uint16_t target = flags;
    int need_write = 0;
    if (do_clear && (flags & 1)) { target = flags & ~1u; need_write = 1; }
    if (do_set && set_val != flags) { target = set_val; need_write = 1; }

    if (need_write) {
        // 备份整个记录
        char bak[128];
        snprintf(bak, sizeof(bak), "ntfs-volume-%llu.bak",
                 (unsigned long long)(rec_off / 1024));
        FILE *f = fopen(bak, "wb");
        if (f) { fwrite(rec, 1, recsize, f); fclose(f); printf("已备份原始记录 -> %s\n", bak); }

        // 在内存里改，再整条记录回写（原始设备要求块对齐）
        uint32_t voff_in_rec = (uint32_t)(flag_off - rec_off);
        rec[voff_in_rec]     = (uint8_t)(target & 0xFF);
        rec[voff_in_rec + 1] = (uint8_t)(target >> 8);

        int wfd = open(dev, O_WRONLY);
        if (wfd < 0) { fprintf(stderr, "以写方式打开 %s 失败: %s\n", dev, strerror(errno)); free(rec); close(fd); return 1; }
        if (pwrite(wfd, rec, recsize, rec_off) != (ssize_t)recsize) {
            fprintf(stderr, "写入失败: %s\n", strerror(errno)); close(wfd); free(rec); close(fd); return 1;
        }
        fsync(wfd);
        close(wfd);

        uint8_t check[2];
        if (pread(fd, check, 2, flag_off) != 2) { fprintf(stderr, "回读失败\n"); free(rec); close(fd); return 1; }
        uint16_t now = rd16(check);
        printf("写入后 flags=0x%04X -> %s\n", now,
               (now == target) ? "成功 ✅" : "与目标不符 ❌");
        if (now != target) { free(rec); close(fd); return 1; }
    }

    free(rec); close(fd);
    return 0;
}
