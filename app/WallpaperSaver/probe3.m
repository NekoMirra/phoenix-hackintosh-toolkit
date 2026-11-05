#import <Cocoa/Cocoa.h>
#import <ScreenSaver/ScreenSaver.h>
#import <objc/runtime.h>
#import <objc/message.h>

// 用法: probe3 <sel> [arg]
// 每次只调一个方法，避免某个方法崩掉整个探查
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: probe3 <selector> [arg]\n"); return 2; }
        [[NSBundle bundleWithPath:@"/System/Library/Frameworks/ScreenSaver.framework"] load];
        Class cls = NSClassFromString(@"ScreenSaverModules");
        id obj = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));

        SEL sel = NSSelectorFromString([NSString stringWithUTF8String:argv[1]]);
        if (![obj respondsToSelector:sel]) {
            printf("[%s] 不支持\n", argv[1]); return 3;
        }
        id r = nil;
        @try {
            if (argc >= 3) {
                r = ((id (*)(id, SEL, id))objc_msgSend)(obj, sel, [NSString stringWithUTF8String:argv[2]]);
            } else {
                r = ((id (*)(id, SEL))objc_msgSend)(obj, sel);
            }
        } @catch (NSException *e) {
            printf("[%s] 异常: %s\n", argv[1], e.reason.UTF8String); return 4;
        }
        if ([r isKindOfClass:[NSArray class]]) {
            printf("[%s] count=%lu\n", argv[1], (unsigned long)[r count]);
            for (id x in r) printf("   %s\n", [[x description] UTF8String]);
        } else {
            printf("[%s] -> %s\n", argv[1], r ? [[r description] UTF8String] : "(nil)");
        }
    }
    return 0;
}
