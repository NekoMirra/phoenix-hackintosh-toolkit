#include <dlfcn.h>
#include <stdio.h>
int main(void) {
    const char *paths[] = {
        "/System/Library/PrivateFrameworks/login.framework/Versions/A/login",
        "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login",
        "/System/Library/PrivateFrameworks/login.framework/login",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        void *h = dlopen(paths[i], RTLD_NOW);
        printf("%s -> %s\n", paths[i], h ? "OK" : dlerror());
        if (h) {
            const char *syms[] = {"SACLockScreenImmediate","SACLockScreen","SACShutdownScreen", NULL};
            for (int j = 0; syms[j]; j++)
                printf("   %-24s %s\n", syms[j], dlsym(h, syms[j]) ? "FOUND" : "missing");
            break;
        }
    }
    return 0;
}
