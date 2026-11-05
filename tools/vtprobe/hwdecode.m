// 实测：强制要求硬件解码器建立 VTDecompressionSession
// 生成一小段 H.264 与 HEVC 视频，然后分别尝试「必须硬件解码」的会话
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

static NSString *tmpPath(NSString *ext) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"vtprobe-%@.%@", [[NSUUID UUID] UUIDString], ext]];
}

// 用 AVAssetWriter 造一段视频，返回文件路径（失败返回 nil）
static NSString *makeMovie(AVVideoCodecType codec, NSString *ext, size_t W, size_t H) {
    NSString *path = tmpPath(ext);
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    NSError *err = nil;
    AVAssetWriter *w = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:path]
                                                fileType:AVFileTypeQuickTimeMovie error:&err];
    if (!w) { printf("    (writer 创建失败: %s)\n", err.localizedDescription.UTF8String); return nil; }

    NSDictionary *settings = @{
        AVVideoCodecKey: codec,
        AVVideoWidthKey: @(W),
        AVVideoHeightKey: @(H)
    };
    AVAssetWriterInput *in = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
    in.expectsMediaDataInRealTime = NO;

    NSDictionary *attrs = @{ (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                             (__bridge NSString *)kCVPixelBufferWidthKey: @(W),
                             (__bridge NSString *)kCVPixelBufferHeightKey: @(H) };
    AVAssetWriterInputPixelBufferAdaptor *ad = [AVAssetWriterInputPixelBufferAdaptor
        assetWriterInputPixelBufferAdaptorWithAssetWriterInput:in sourcePixelBufferAttributes:attrs];

    if (![w canAddInput:in]) { printf("    (无法添加输入)\n"); return nil; }
    [w addInput:in];
    if (![w startWriting]) { printf("    (startWriting 失败: %s)\n", w.error.localizedDescription.UTF8String); return nil; }
    [w startSessionAtSourceTime:kCMTimeZero];

    for (int i = 0; i < 6; i++) {
        CVPixelBufferRef pb = NULL;
        if (CVPixelBufferPoolCreatePixelBuffer(NULL, ad.pixelBufferPool, &pb) != kCVReturnSuccess || !pb) break;
        CVPixelBufferLockBaseAddress(pb, 0);
        memset(CVPixelBufferGetBaseAddress(pb), i * 20, CVPixelBufferGetDataSize(pb));
        CVPixelBufferUnlockBaseAddress(pb, 0);
        while (!in.isReadyForMoreMediaData) usleep(2000);
        [ad appendPixelBuffer:pb withPresentationTime:CMTimeMake(i, 30)];
        CVPixelBufferRelease(pb);
    }
    [in markAsFinished];
    __block BOOL done = NO;
    [w finishWritingWithCompletionHandler:^{ done = YES; }];
    for (int i = 0; i < 3000 && !done; i++) usleep(2000);
    if (w.status != AVAssetWriterStatusCompleted) {
        printf("    (写入未完成, status=%ld)\n", (long)w.status);
        return nil;
    }
    return path;
}

static void tryDecode(NSString *path, const char *label) {
    AVURLAsset *a = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:path]];
    AVAssetTrack *t = [[a tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!t) { printf("  %-6s 取不到视频轨\n", label); return; }
    NSArray *fds = t.formatDescriptions;
    if (!fds.count) { printf("  %-6s 取不到格式描述\n", label); return; }
    CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)fds[0];

    NSDictionary *req = @{ (__bridge NSString *)kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: @YES };
    VTDecompressionSessionRef s = NULL;
    OSStatus st = VTDecompressionSessionCreate(kCFAllocatorDefault, fd, (__bridge CFDictionaryRef)req,
                                               NULL, NULL, &s);
    if (st == noErr && s) {
        printf("  %-6s ✅ 能建立「必须硬件」解码会话（走 NVDEC）\n", label);
        VTDecompressionSessionInvalidate(s);
        CFRelease(s);
    } else {
        printf("  %-6s ❌ 无法建立硬件解码会话 (OSStatus=%d)\n", label, (int)st);
    }
}

int main(void) {
    @autoreleasepool {
        printf("=== 强制硬件解码实测（640x480）===\n");
        NSString *h264 = makeMovie(AVVideoCodecTypeH264, @"mov", 640, 480);
        if (h264) { tryDecode(h264, "H.264"); }
        else printf("  H.264  样例生成失败，跳过\n");

        NSString *hevc = makeMovie(AVVideoCodecTypeHEVC, @"mov", 640, 480);
        if (hevc) { tryDecode(hevc, "HEVC"); }
        else printf("  HEVC   样例生成失败（本机可能无 HEVC 编码器）\n");
    }
    return 0;
}
