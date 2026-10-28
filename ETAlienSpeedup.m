/**
 * ETAlienSpeedup.m - 外星仔加速器激励广告极速秒跳与自动关弹窗插件
 * 适用环境: iOS 15.0 - 17.0 (TrollStore + TrollFools / 越狱环境)
 * 目标 App: 外星仔加速器 (com.etalien.booster)
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#define SPEED_MULTIPLIER 32.0f // 视频播放加速倍率 (16.0 ~ 32.0)

#pragma mark - 1. AVPlayer 播放器全局倍速 Hook (让 40 秒长视频在 1 秒内播放完毕)

static void (*orig_AVPlayer_setRate)(id self, SEL _cmd, float rate);
static void my_AVPlayer_setRate(id self, SEL _cmd, float rate) {
    if (rate > 0.0f) {
        // 只要播放器开始播放，强制拉高至超高倍速
        rate = SPEED_MULTIPLIER;
    }
    if (orig_AVPlayer_setRate) {
        orig_AVPlayer_setRate(self, _cmd, rate);
    }
}

static void (*orig_AVPlayer_play)(id self, SEL _cmd);
static void my_AVPlayer_play(id self, SEL _cmd) {
    if (orig_AVPlayer_play) {
        orig_AVPlayer_play(self, _cmd);
    }
    // 强制把播放速率拉到 32 倍速
    if ([self respondsToSelector:@selector(setRate:)]) {
        [self setRate:SPEED_MULTIPLIER];
    }
}

#pragma mark - 2. GroMore 广告页面弹窗自动关闭 Hook (告别快手等广告的手动点叉)

// 针对 flutter_gromore_ads 插件的核心承载类 FGMRewardVideoPage
static void (*orig_didPlayFinish)(id self, SEL _cmd, id ad, id error);
static void my_didPlayFinish(id self, SEL _cmd, id ad, id error) {
    NSLog(@"[ETAlienSpeedup] 广告视频播放完毕，准备自动跳过弹窗并结算发奖...");
    
    // 1. 先调用原始方法，确保 SDK 内部标记已完播
    if (orig_didPlayFinish) {
        orig_didPlayFinish(self, _cmd, ad, error);
    }
    
    // 2. 延迟 0.3 秒自动调用广告关闭，绕过 End-Card 结算页
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SEL closeSel = NSSelectorFromString(@"nativeExpressRewardedVideoAdDidClose:");
        if ([self respondsToSelector:closeSel]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [self performSelector:closeSel withObject:ad];
            #pragma clang diagnostic pop
            NSLog(@"[ETAlienSpeedup] 已自动触发 nativeExpressRewardedVideoAdDidClose:");
        }
        
        // 3. 自动 Dismiss 当前弹出的广告 UIViewController
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        if (rootVC && rootVC != [UIApplication sharedApplication].keyWindow.rootViewController) {
            [rootVC dismissViewControllerAnimated:YES completion:nil];
            NSLog(@"[ETAlienSpeedup] 已自动关闭广告顶层视图控制器");
        }
    });
}

#pragma mark - 3. 拦截广告验证失败，自动重试 (避免“获取奖励失败”手动点重试)

static void (*orig_serverRewardFail)(id self, SEL _cmd, id error);
static void my_serverRewardFail(id self, SEL _cmd, id error) {
    NSLog(@"[ETAlienSpeedup] 捕获到奖励回调失败，错误: %@，尝试自动补调成功回调...", error);
    
    // 强行尝试触发一次成功回调
    SEL succeedSel = NSSelectorFromString(@"nativeExpressRewardedVideoAdServerRewardDidSucceed:verify:");
    if ([self respondsToSelector:succeedSel]) {
        NSMethodSignature *sig = [self methodSignatureForSelector:succeedSel];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:self];
            [inv setSelector:succeedSel];
            id adObj = nil;
            BOOL verify = YES;
            [inv setArgument:&adObj atIndex:2];
            [inv setArgument:&verify atIndex:3];
            [inv invoke];
            NSLog(@"[ETAlienSpeedup] 强制补调 nativeExpressRewardedVideoAdServerRewardDidSucceed 成功");
        }
    }
    
    if (orig_serverRewardFail) {
        orig_serverRewardFail(self, _cmd, error);
    }
}

#pragma mark - 4. 插件入口与 Hook 初始化

static void swizzleInstanceMethod(Class cls, SEL origSel, IMP newImp, IMP *origImp) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, origSel);
    if (!m) return;
    if (origImp) {
        *origImp = method_getImplementation(m);
    }
    method_setImplementation(m, newImp);
}

__attribute__((constructor)) static void initSpeedupPlugin(void) {
    NSLog(@"[ETAlienSpeedup] 插件已注入外星仔加速器，正在应用倍速与免关弹窗补丁...");
    
    // 1. Hook AVPlayer (实现全局视频 32 倍速播放)
    Class avPlayerClass = objc_getClass("AVPlayer");
    if (avPlayerClass) {
        swizzleInstanceMethod(avPlayerClass, @selector(setRate:), (IMP)my_AVPlayer_setRate, (IMP *)&orig_AVPlayer_setRate);
        swizzleInstanceMethod(avPlayerClass, @selector(play), (IMP)my_AVPlayer_play, (IMP *)&orig_AVPlayer_play);
        NSLog(@"[ETAlienSpeedup] AVPlayer 倍速 Hook 成功 (当前设置: %.0fx)", SPEED_MULTIPLIER);
    }
    
    // 2. Hook FGMRewardVideoPage (实现完播自动关闭与跳过弹窗)
    Class fgmClass = objc_getClass("FGMRewardVideoPage");
    if (fgmClass) {
        SEL finishSel = NSSelectorFromString(@"nativeExpressRewardedVideoAdDidPlayFinish:didFailWithError:");
        swizzleInstanceMethod(fgmClass, finishSel, (IMP)my_didPlayFinish, (IMP *)&orig_didPlayFinish);
        
        SEL failSel = NSSelectorFromString(@"nativeExpressRewardedVideoAdServerRewardDidFail:error:");
        swizzleInstanceMethod(fgmClass, failSel, (IMP)my_serverRewardFail, (IMP *)&orig_serverRewardFail);
        NSLog(@"[ETAlienSpeedup] FGMRewardVideoPage 自动关闭与重试 Hook 成功");
    }
    
    NSLog(@"[ETAlienSpeedup] 初始化完毕！");
}
