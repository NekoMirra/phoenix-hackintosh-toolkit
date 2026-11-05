// WallpaperSaverView.m
// 一个「把当前壁纸原样铺满」的屏保。
// 图片以 wallpaper.jpg 的形式内嵌在 .saver 包里，避免 legacyScreenSaver
// 沙箱读不到外部卷（/Volumes/数据）的问题。

#import <ScreenSaver/ScreenSaver.h>
#import <AppKit/AppKit.h>

@interface WallpaperSaverView : ScreenSaverView {
    NSImage *_image;
    NSString *_imagePath;
}
@end

@implementation WallpaperSaverView

- (NSString *)resourcePathForImage {
    NSBundle *b = [NSBundle bundleForClass:[self class]];
    NSString *p = [b pathForResource:@"wallpaper" ofType:@"jpg"];
    if (!p) p = [b pathForResource:@"wallpaper" ofType:@"png"];
    if (!p) {
        // 兜底：跟着 bundle 找
        NSString *res = [[b resourcePath] stringByAppendingPathComponent:@"wallpaper.jpg"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:res]) p = res;
    }
    return p;
}

- (void)loadImage {
    _imagePath = [self resourcePathForImage];
    if (_imagePath) {
        _image = [[NSImage alloc] initWithContentsOfFile:_imagePath];
        // 让 NSImage 一次解码，避免每帧重复解码 5000px 大图
        [_image setCacheMode:NSImageCacheAlways];
    }
}

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        [self setAnimationTimeInterval:5.0];   // 静态图，不需要动画
        [self loadImage];
    }
    return self;
}

- (void)startAnimation {
    [super startAnimation];
    if (!_image) [self loadImage];
}

- (void)animateOneFrame {
    // 静态：什么都不做
}

- (void)drawRect:(NSRect)rect {
    [[NSColor blackColor] setFill];
    NSRectFill(self.bounds);

    if (!_image) { [self loadImage]; }
    if (!_image) return;

    NSSize is = [_image size];
    NSRect b = self.bounds;
    if (is.width <= 0 || is.height <= 0 || b.size.width <= 0 || b.size.height <= 0) return;

    // 等比铺满（aspect fill）—— 与壁纸的「填充/裁剪」一致
    CGFloat scale = MAX(b.size.width / is.width, b.size.height / is.height);
    CGFloat w = is.width * scale;
    CGFloat h = is.height * scale;
    NSRect target = NSMakeRect(b.origin.x + (b.size.width - w) / 2.0,
                               b.origin.y + (b.size.height - h) / 2.0,
                               w, h);

    [_image drawInRect:target
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1.0
        respectFlipped:YES
                 hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
}

- (BOOL)hasConfigureSheet { return NO; }
- (NSWindow *)configureSheet { return nil; }

@end
