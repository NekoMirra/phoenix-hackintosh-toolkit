// 自检：加载 .saver 包，实例化主类，离屏渲染成 PNG
#import <Cocoa/Cocoa.h>
#import <ScreenSaver/ScreenSaver.h>
#import <objc/runtime.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: savertest <saver> <out.png> [w h]\n"); return 2; }
        NSString *saverPath = [NSString stringWithUTF8String:argv[1]];
        NSString *outPath   = [NSString stringWithUTF8String:argv[2]];
        CGFloat w = argc > 3 ? atof(argv[3]) : 1280;
        CGFloat h = argc > 4 ? atof(argv[4]) : 800;

        NSBundle *b = [NSBundle bundleWithPath:saverPath];
        if (!b) { fprintf(stderr, "无法加载 bundle\n"); return 1; }
        NSError *err = nil;
        if (![b loadAndReturnError:&err]) {
            fprintf(stderr, "load 失败: %s\n", err.localizedDescription.UTF8String);
            return 1;
        }
        Class cls = b.principalClass;
        if (!cls) { fprintf(stderr, "principalClass 为空\n"); return 1; }
        printf("principalClass = %s\n", class_getName(cls));

        NSRect frame = NSMakeRect(0, 0, w, h);
        ScreenSaverView *v = [[cls alloc] initWithFrame:frame isPreview:NO];
        if (!v) { fprintf(stderr, "实例化失败\n"); return 1; }
        printf("view = %s  frame=%.0fx%.0f\n", class_getName([v class]), v.frame.size.width, v.frame.size.height);

        [v startAnimation];

        NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
        if (!rep) { fprintf(stderr, "bitmap rep 失败\n"); return 1; }
        [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (![png writeToFile:outPath atomically:YES]) { fprintf(stderr, "写 PNG 失败\n"); return 1; }
        printf("已渲染 -> %s (%lu bytes)\n", outPath.UTF8String, (unsigned long)png.length);
    }
    return 0;
}
