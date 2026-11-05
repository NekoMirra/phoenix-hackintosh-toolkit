#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreGraphics/CoreGraphics.h>

static void listEncoders(void) {
    CFArrayRef list = NULL;
    VTCopyVideoEncoderList(NULL, &list);
    printf("=== 编码器（硬件加速标记）===\n");
    if (!list) { printf("  (无编码器列表)\n"); return; }
    for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
        CFDictionaryRef d = CFArrayGetValueAtIndex(list, i);
        CFStringRef nm = CFDictionaryGetValue(d, kVTVideoEncoderList_CodecName);
        CFStringRef dn = CFDictionaryGetValue(d, kVTVideoEncoderList_DisplayName);
        CFNumberRef hw = CFDictionaryGetValue(d, kVTVideoEncoderList_IsHardwareAccelerated);
        char a[96] = "", b[96] = "";
        int h = 0;
        if (nm) CFStringGetCString(nm, a, sizeof(a), kCFStringEncodingUTF8);
        if (dn) CFStringGetCString(dn, b, sizeof(b), kCFStringEncodingUTF8);
        if (hw) CFNumberGetValue(hw, kCFNumberIntType, &h);
        if (h || strstr(a, "HEVC") || strstr(a, "H.264"))
            printf("  %-12s %-24s 硬件=%s\n", a, b, h ? "是" : "否");
    }
}

static void listModes(void) {
    CGDirectDisplayID d = CGMainDisplayID();
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(d, NULL);
    printf("\n=== 主显示器模式（已去重）===\n");
    if (!modes) { printf("  (取不到模式)\n"); return; }
    NSMutableSet *seen = [NSMutableSet set];
    for (CFIndex i = 0; i < CFArrayGetCount(modes); i++) {
        CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
        size_t pw = CGDisplayModeGetPixelWidth(m), ph = CGDisplayModeGetPixelHeight(m);
        size_t lw = CGDisplayModeGetWidth(m), lh = CGDisplayModeGetHeight(m);
        double hz = CGDisplayModeGetRefreshRate(m);
        NSString *k = [NSString stringWithFormat:@"%zux%zu@%.0f", lw, lh, hz];
        if ([seen containsObject:k]) continue;
        [seen addObject:k];
        printf("  逻辑 %4zux%-4zu  像素 %4zux%-4zu  %3.0fHz  HiDPI=%s\n",
               lw, lh, pw, ph, hz, (pw > lw) ? "是" : "否");
    }
}

int main(void) {
    @autoreleasepool { listEncoders(); listModes(); }
    return 0;
}
