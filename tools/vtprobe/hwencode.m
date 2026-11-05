// 实测：强制要求硬件编码器建立 VTCompressionSession
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

static void tryEncode(CMVideoCodecType codec, const char *label, int w, int h) {
    NSDictionary *spec = @{ (__bridge NSString *)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: @YES };
    VTCompressionSessionRef s = NULL;
    OSStatus st = VTCompressionSessionCreate(kCFAllocatorDefault, w, h,
                                             (OSType)codec, (__bridge CFDictionaryRef)spec,
                                             NULL, NULL, NULL, NULL, &s);
    if (st == noErr && s) {
        printf("  %-6s ✅ 可建立「必须硬件」编码会话（走 NVENC）\n", label);
        VTCompressionSessionInvalidate(s);
        CFRelease(s);
    } else {
        printf("  %-6s ❌ 无法建立硬件编码会话 (OSStatus=%d)\n", label, (int)st);
    }
}

int main(void) {
    @autoreleasepool {
        printf("=== 强制硬件编码实测（1280x720）===\n");
        tryEncode(kCMVideoCodecType_H264, "H.264", 1280, 720);
        tryEncode(kCMVideoCodecType_HEVC, "HEVC", 1280, 720);
        printf("\n（仅建立会话，不做实际编码）\n");
    }
    return 0;
}
