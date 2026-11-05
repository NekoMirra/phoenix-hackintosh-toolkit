#include <VideoToolbox/VideoToolbox.h>
#include <CoreMedia/CoreMedia.h>
#include <stdio.h>
int main(void) {
    struct { const char *name; CMVideoCodecType t; } c[] = {
        {"H.264", kCMVideoCodecType_H264},
        {"HEVC",  kCMVideoCodecType_HEVC},
        {"VP9",   kCMVideoCodecType_VP9},
        {"ProRes422", kCMVideoCodecType_AppleProRes422},
    };
    printf("=== 硬件解码支持 ===\n");
    for (int i = 0; i < 4; i++)
        printf("  %-10s %s\n", c[i].name, VTIsHardwareDecodeSupported(c[i].t) ? "支持" : "不支持");

    printf("\n=== 编码器列表 ===\n");
    CFArrayRef list = NULL;
    VTCopyVideoEncoderList(NULL, &list);
    if (list) {
        CFIndex n = CFArrayGetCount(list);
        for (CFIndex i = 0; i < n; i++) {
            CFDictionaryRef d = CFArrayGetValueAtIndex(list, i);
            CFStringRef nm = CFDictionaryGetValue(d, kVTVideoEncoderList_CodecName);
            CFStringRef dn = CFDictionaryGetValue(d, kVTVideoEncoderList_DisplayName);
            char buf[128] = "", buf2[128] = "";
            if (nm) CFStringGetCString(nm, buf, sizeof(buf), kCFStringEncodingUTF8);
            if (dn) CFStringGetCString(dn, buf2, sizeof(buf2), kCFStringEncodingUTF8);
            printf("  %s | %s\n", buf, buf2);
        }
    }
    return 0;
}
