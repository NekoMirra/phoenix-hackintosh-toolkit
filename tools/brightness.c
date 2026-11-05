// brightness.c - read/write display brightness via DisplayServices private framework
// usage: brightness            -> print current brightness of all online displays
//        brightness 0.4        -> set brightness 40% on main display
//        brightness -w 0.4 3   -> watch every 3s
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>
#include <CoreGraphics/CoreGraphics.h>

typedef int (*GetFn)(CGDirectDisplayID, float *);
typedef int (*SetFn)(CGDirectDisplayID, float);
typedef int (*CanFn)(CGDirectDisplayID);

int main(int argc, char **argv) {
    void *h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 2; }
    GetFn get = (GetFn)dlsym(h, "DisplayServicesGetBrightness");
    SetFn set = (SetFn)dlsym(h, "DisplayServicesSetBrightness");
    CanFn can = (CanFn)dlsym(h, "DisplayServicesCanChangeBrightness");
    if (!get) { fprintf(stderr, "no DisplayServicesGetBrightness\n"); return 2; }

    if (argc >= 2 && strcmp(argv[1], "-q") == 0) {
        float b = 0.0f;
        if (get(CGMainDisplayID(), &b) != 0) return 1;
        printf("%.4f\n", b);
        return 0;
    }
    if (argc >= 2 && strcmp(argv[1], "-w") != 0) {
        if (!set) { fprintf(stderr, "no setter\n"); return 2; }
        float v = (float)atof(argv[1]);
        CGDirectDisplayID m = CGMainDisplayID();
        int r = set(m, v);
        printf("set display 0x%x -> %.3f ret=%d\n", m, v, r);
        return 0;
    }

    int watch = (argc >= 2 && strcmp(argv[1], "-w") == 0);
    int interval = 3;
    if (watch && argc >= 3) interval = atoi(argv[2]);
    if (interval <= 0) interval = 3;

    do {
        uint32_t n = 0;
        CGGetOnlineDisplayList(16, NULL, &n);
        CGDirectDisplayID ids[16];
        CGGetOnlineDisplayList(16, ids, &n);
        printf("[%ld] displays=%u", (long)time(NULL), n);
        for (uint32_t i = 0; i < n; i++) {
            float b = -1.0f;
            int r = get(ids[i], &b);
            int c = can ? can(ids[i]) : -1;
            printf(" | 0x%x%s b=%.4f (%.1f%%) ret=%d can=%d",
                   ids[i], ids[i] == CGMainDisplayID() ? "*" : "", b, b * 100.0f, r, c);
        }
        printf("\n");
        fflush(stdout);
        if (watch) sleep(interval);
    } while (watch);
    return 0;
}
