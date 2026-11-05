// locknow —— 立即锁定屏幕
// 优先调用 login.framework 的 SACLockScreenImmediate（系统原生锁屏）
// 失败时回退到 pmset displaysleepnow（熄屏，配合"立即要求密码"同样达到锁定效果）
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

static int run(char *const argv[]) {
    pid_t p = fork();
    if (p < 0) return -1;
    if (p == 0) { execv(argv[0], argv); _exit(127); }
    int st = 0;
    if (waitpid(p, &st, 0) < 0) return -1;
    return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

int main(void) {
    const char *paths[] = {
        "/System/Library/PrivateFrameworks/login.framework/Versions/A/login",
        "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login",
        "/System/Library/PrivateFrameworks/login.framework/login",
        NULL
    };

    for (int i = 0; paths[i]; i++) {
        void *h = dlopen(paths[i], RTLD_LAZY);
        if (!h) continue;
        int (*lock)(void) = (int (*)(void))dlsym(h, "SACLockScreenImmediate");
        if (lock) {
            int rc = lock();
            if (rc == 0) return 0;
            fprintf(stderr, "SACLockScreenImmediate 返回 %d，回退熄屏\n", rc);
            break;
        }
    }

    char *argv[] = { "/usr/bin/pmset", "displaysleepnow", NULL };
    return run(argv) == 0 ? 0 : 1;
}
