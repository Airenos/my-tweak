/**
 * ETAlienSpeedup.m - 外星仔加速器极速快进 + 节点提取插件
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
    if ([self respondsToSelector:@selector(setRate:)]) {
        [self setRate:SPEED_MULTIPLIER];
    }
}

#pragma mark - 2. GroMore 广告页面弹窗自动关闭 Hook (告别快手等广告的手动点叉)

static void (*orig_didPlayFinish)(id self, SEL _cmd, id ad, id error);
static void my_didPlayFinish(id self, SEL _cmd, id ad, id error) {
    NSLog(@"[ETAlienSpeedup] 广告视频播放完毕，准备自动跳过弹窗并结算发奖...");
    
    if (orig_didPlayFinish) {
        orig_didPlayFinish(self, _cmd, ad, error);
    }
    
    // 延迟 0.3 秒自动调用广告关闭，绕过 End-Card 结算页
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SEL closeSel = NSSelectorFromString(@"nativeExpressRewardedVideoAdDidClose:");
        if ([self respondsToSelector:closeSel]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [self performSelector:closeSel withObject:ad];
            #pragma clang diagnostic pop
            NSLog(@"[ETAlienSpeedup] 已自动触发 nativeExpressRewardedVideoAdDidClose:");
        }
        
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

#pragma mark - 3. 拦截广告验证失败，自动补发成功

static void (*orig_serverRewardFail)(id self, SEL _cmd, id error);
static void my_serverRewardFail(id self, SEL _cmd, id error) {
    NSLog(@"[ETAlienSpeedup] 捕获到奖励回调失败，错误: %@，尝试自动补调成功回调...", error);
    
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

#pragma mark - 4. 方案 2: 加速专线节点自动抓取与导出 (提取电竞级低延迟节点)

static void saveNodeConfigToFile(NSString *info) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count == 0) return;
    NSString *docDir = paths[0];
    NSString *filePath = [docDir stringByAppendingPathComponent:@"booster_nodes.txt"];
    
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                        dateStyle:NSDateFormatterShortStyle
                                                        timeStyle:NSDateFormatterMediumStyle];
    NSString *logLine = [NSString stringWithFormat:@"\n[%@] 专线节点信息:\n%@\n----------------------------", timestamp, info];
    
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    } else {
        [logLine writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    NSLog(@"[ETAlienSpeedup] 节点信息已保存至: %@", filePath);
}

// 监听系统通知，当 VPN 节点更新时捕获节点参数
static void onVpnNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notifName = (__bridge NSString *)name;
    NSDictionary *info = (__bridge NSDictionary *)userInfo;
    NSLog(@"[ETAlienSpeedup] 捕获到 VPN 状态通知: %@, 数据: %@", notifName, info);
    if (info) {
        saveNodeConfigToFile([NSString stringWithFormat:@"%@ -> %@", notifName, info]);
    }
}

#pragma mark - 5. 插件入口与 Hook 初始化

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
    NSLog(@"[ETAlienSpeedup] 插件已注入外星仔加速器，正在应用倍速、自动关弹窗与节点抓取补丁...");
    
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
    
    // 3. 监听外星仔底层的专线节点更新通知 (方案 2: 提取低延迟专线配置)
    NSNotificationCenter *dc = [NSNotificationCenter defaultCenter];
    [dc addObserverForName:@"com.etalien.booster.ETAlienBoosterSDK.BoosterUpdate"
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification * _Nonnull note) {
        NSLog(@"[ETAlienSpeedup] 收到 BoosterUpdate 通知: %@", note.userInfo);
        if (note.userInfo) {
            saveNodeConfigToFile([NSString stringWithFormat:@"BoosterUpdate: %@", note.userInfo]);
        }
    }];
    
    [dc addObserverForName:@"com.etalien.booster.ETAlienBoosterSDK.BoosterProfileUpdate"
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification * _Nonnull note) {
        NSLog(@"[ETAlienSpeedup] 收到 BoosterProfileUpdate 节点参数: %@", note.userInfo);
        if (note.userInfo) {
            saveNodeConfigToFile([NSString stringWithFormat:@"BoosterProfileUpdate: %@", note.userInfo]);
        }
    }];

    NSLog(@"[ETAlienSpeedup] 初始化完毕！专线节点监听已就绪。");
}
