// 通过 ScreenSaver.framework 的私有类枚举系统认到的屏保模块
#import <Cocoa/Cocoa.h>
#import <ScreenSaver/ScreenSaver.h>
#import <objc/runtime.h>
#import <objc/message.h>

int main(void) {
    @autoreleasepool {
        NSBundle *fw = [NSBundle bundleWithPath:@"/System/Library/Frameworks/ScreenSaver.framework"];
        [fw load];

        Class cls = NSClassFromString(@"ScreenSaverModules");
        if (!cls) { fprintf(stderr, "找不到 ScreenSaverModules\n"); return 1; }

        id shared = nil;
        if ([cls respondsToSelector:@selector(sharedInstance)]) {
            shared = [cls performSelector:@selector(sharedInstance)];
        } else if ([cls respondsToSelector:@selector(sharedManager)]) {
            shared = [cls performSelector:@selector(sharedManager)];
        }
        if (!shared) { fprintf(stderr, "拿不到共享实例\n"); return 1; }
        printf("ScreenSaverModules = %p\n\n", shared);

        // 打印所有可读属性/方法，便于挑
        unsigned int n = 0;
        Method *ms = class_copyMethodList(cls, &n);
        printf("--- 类方法 ---\n");
        for (unsigned i = 0; i < n; i++) printf("  %s\n", sel_getName(method_getName(ms[i])));
        free(ms);

        Class c2 = object_getClass(shared);
        n = 0;
        Method *ms2 = class_copyMethodList(c2, &n);
        printf("--- 实例方法 ---\n");
        for (unsigned i = 0; i < n; i++) printf("  %s\n", sel_getName(method_getName(ms2[i])));
        free(ms2);

        // 尝试直接向 bundle 查询
        printf("\n--- 查询我们的包（初始化前）---\n");
        NSString *p = [@"~/Library/Screen Savers/WallpaperSaver.saver" stringByExpandingTildeInPath];
        SEL s = NSSelectorFromString(@"moduleWithPath:");
        if ([shared respondsToSelector:s]) {
            id m = ((id (*)(id, SEL, id))objc_msgSend)(shared, s, p);
            printf("moduleWithPath -> %s\n", m ? [[m description] UTF8String] : "(nil)");
        }

        printf("\n--- 初始化模块表 ---\n");
        SEL ini = NSSelectorFromString(@"_initializeModules");
        if ([cls respondsToSelector:ini]) { ((void (*)(id, SEL))objc_msgSend)(cls, ini); printf("  _initializeModules 已调用\n"); }

        printf("\n--- 搜索目录 ---\n");
        SEL sd = NSSelectorFromString(@"moduleSearchDomains");
        if ([cls respondsToSelector:sd]) {
            id doms = ((id (*)(id, SEL))objc_msgSend)(cls, sd);
            printf("%s\n", [[doms description] UTF8String]);
        }

        printf("\n--- 模块名列表 ---\n");
        SEL mn = NSSelectorFromString(@"moduleNames");
        if ([cls respondsToSelector:mn]) {
            id names = ((id (*)(id, SEL))objc_msgSend)(cls, mn);
            printf("%s\n", [[names description] UTF8String]);
        }

        printf("\n--- 强制重建模块表 ---\n");
        SEL fm = NSSelectorFromString(@"findModulesWithOrder:forceRebuild:");
        if ([cls respondsToSelector:fm]) {
            id arr = ((id (*)(id, SEL, BOOL, BOOL))objc_msgSend)(cls, fm, NO, YES);
            printf("count=%lu\n", (unsigned long)[arr count]);
            for (id mod in arr) {
                NSString *name = [mod valueForKey:@"name"];
                NSString *path = [mod valueForKey:@"path"];
                printf("  name=%-28s path=%s\n",
                       name ? [name UTF8String] : "?",
                       path ? [path UTF8String] : "?");
            }
        } else {
            printf("(无此方法)\n");
        }
    }
    return 0;
}
