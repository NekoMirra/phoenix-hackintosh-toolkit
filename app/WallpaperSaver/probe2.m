#import <Cocoa/Cocoa.h>
#import <ScreenSaver/ScreenSaver.h>
#import <objc/runtime.h>
#import <objc/message.h>

int main(void) {
    @autoreleasepool {
        [[NSBundle bundleWithPath:@"/System/Library/Frameworks/ScreenSaver.framework"] load];
        Class cls = NSClassFromString(@"ScreenSaverModules");
        if (!cls) { fprintf(stderr, "no class\n"); return 1; }

        // 拿到单例（可能是实例，也可能是类本身）
        id obj = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
        printf("obj=%p isClass=%d\n", obj, class_isMetaClass(object_getClass(obj)));

        struct { const char *sel; } calls[] = {
            {"_initializeModules"}, {"moduleNames"}, {"moduleSearchDomains"}
        };
        for (int i = 0; i < 3; i++) {
            SEL s = NSSelectorFromString([NSString stringWithUTF8String:calls[i].sel]);
            if (![obj respondsToSelector:s]) {
                printf("[%s] 不支持\n", calls[i].sel);
                continue;
            }
            id r = ((id (*)(id, SEL))objc_msgSend)(obj, s);
            printf("[%s] -> %s\n", calls[i].sel, r ? [[r description] UTF8String] : "(nil)");
        }

        NSString *p = [@"~/Library/Screen Savers/WallpaperSaver.saver" stringByExpandingTildeInPath];
        SEL s2 = NSSelectorFromString(@"moduleWithPath:");
        if ([obj respondsToSelector:s2]) {
            id m = ((id (*)(id, SEL, id))objc_msgSend)(obj, s2, p);
            printf("moduleWithPath(WallpaperSaver) -> %s\n", m ? [[m description] UTF8String] : "(nil)");
        }
        SEL s3 = NSSelectorFromString(@"moduleWithName:");
        if ([obj respondsToSelector:s3]) {
            id m = ((id (*)(id, SEL, id))objc_msgSend)(obj, s3, @"WallpaperSaver");
            printf("moduleWithName(WallpaperSaver) -> %s\n", m ? [[m description] UTF8String] : "(nil)");
        }
    }
    return 0;
}
