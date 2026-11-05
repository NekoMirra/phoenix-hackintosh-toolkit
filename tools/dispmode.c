// dispmode — 列出/切换 macOS 显示模式（刷新率、分辨率）
// 编译: clang -framework CoreGraphics -framework Foundation -o dispmode dispmode.c
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void list_modes(void) {
    CGDirectDisplayID displays[8];
    uint32_t n = 0;
    CGGetActiveDisplayList(8, displays, &n);

    for (uint32_t i = 0; i < n; i++) {
        CGDirectDisplayID d = displays[i];
        CGDisplayModeRef cur = CGDisplayCopyDisplayMode(d);
        printf("== Display %u (id=%u) %s ==\n", i, d,
               CGDisplayIsMain(d) ? "[MAIN]" : "");
        printf("   current: %zux%zu @ %.2f Hz\n",
               CGDisplayModeGetWidth(cur),
               CGDisplayModeGetHeight(cur),
               CGDisplayModeGetRefreshRate(cur));
        CGDisplayModeRelease(cur);

        CFArrayRef modes = CGDisplayCopyAllDisplayModes(d, NULL);
        if (!modes) continue;
        CFIndex cnt = CFArrayGetCount(modes);
        printf("   %ld modes:\n", (long)cnt);
        for (CFIndex k = 0; k < cnt; k++) {
            CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, k);
            double hz = CGDisplayModeGetRefreshRate(m);
            printf("     [%3ld] %zux%zu  %.2f Hz  pixel=%zux%zu  depth=%zu\n",
                   (long)k,
                   CGDisplayModeGetWidth(m), CGDisplayModeGetHeight(m), hz,
                   CGDisplayModeGetPixelWidth(m), CGDisplayModeGetPixelHeight(m),
                   CGDisplayModeGetIOFlags(m) ? 0 : 0);
        }
        CFRelease(modes);
    }
}

static int set_mode(const char *dispSel, size_t w, size_t h, double hz) {
    CGDirectDisplayID displays[8];
    uint32_t n = 0;
    CGGetActiveDisplayList(8, displays, &n);
    CGDirectDisplayID target = displays[0];
    if (dispSel && strcmp(dispSel, "-") != 0) {
        unsigned idx = (unsigned)atoi(dispSel);
        if (idx < n) target = displays[idx];
    }

    CFArrayRef modes = CGDisplayCopyAllDisplayModes(target, NULL);
    if (!modes) { fprintf(stderr, "no modes\n"); return 1; }

    CGDisplayModeRef best = NULL;
    for (CFIndex k = 0; k < CFArrayGetCount(modes); k++) {
        CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, k);
        if (CGDisplayModeGetWidth(m) != w || CGDisplayModeGetHeight(m) != h) continue;
        double mhz = CGDisplayModeGetRefreshRate(m);
        if (hz > 0 && (mhz < hz - 0.6 || mhz > hz + 0.6)) continue;
        if (!best) { best = m; continue; }
        // 优先选像素尺寸等于逻辑尺寸的（非缩放），否则取最接近目标刷新率
        if (hz <= 0) {
            if (CGDisplayModeGetRefreshRate(m) < CGDisplayModeGetRefreshRate(best)) best = m;
        }
    }
    if (!best) {
        fprintf(stderr, "no matching mode %zux%zu @ %.0fHz\n", w, h, hz);
        CFRelease(modes);
        return 2;
    }
    CGError err = CGDisplaySetDisplayMode(target, best, NULL);
    printf("set %zux%zu @ %.2f Hz -> %s\n", w, h,
           CGDisplayModeGetRefreshRate(best), err == kCGErrorSuccess ? "OK" : "FAILED");
    CFRelease(modes);
    return err == kCGErrorSuccess ? 0 : 3;
}

int main(int argc, char **argv) {
    if (argc >= 2 && strcmp(argv[1], "list") == 0) { list_modes(); return 0; }
    if (argc >= 5 && strcmp(argv[1], "set") == 0) {
        return set_mode(argv[2], (size_t)atoi(argv[3]), (size_t)atoi(argv[4]),
                        argc >= 6 ? atof(argv[5]) : 0);
    }
    fprintf(stderr, "usage: %s list | set <displayIdx|-> <w> <h> [hz]\n", argv[0]);
    return 1;
}
