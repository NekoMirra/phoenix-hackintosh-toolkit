/*
 * kmod_info.c — 提供链接器必需的 _kmod_info 符号。
 * 没有完整 Xcode 时，必须手写这个文件，否则 kmutil 报
 * "kexts must have a _kmod_info symbol"。
 */
#include <mach/mach_types.h>
#include <mach/kmod.h>

extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);

KMOD_EXPLICIT_DECL(wtf.local.AMDProbe, "1.0.0", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = 0;
__private_extern__ kmod_stop_func_t *_antimain = 0;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
