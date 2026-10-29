/**
 * ETAlienSpeedup.m v2.0 - 外星仔加速器全能强化插件
 * 
 * 核心升级:
 * 1. [新增] NSTimer 全局倒计时 16 倍速加速 (解决 P1/P2 图中“去浏览10秒减时长”、“45秒后可领奖”等 H5/落地页倒计时)
 * 2. [新增] 拦截淘宝/外链跳转 (openURL)，假装已经去外部浏览了 10 秒并返回，不跳出 App 也能直接减时长
 * 3. [保留] AVPlayer 32 倍速视频快进 (针对纯视频广告)
 * 4. [保留] 广告播完自动关闭页面 (FGMRewardVideoPage)
 * 5. [修复] 专线节点提取: 自动定位 App Group (group.etalien.booster)，自动复制 booster_config.json 到 Documents/booster_nodes.txt
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#define TIMER_ACCELERATION 16.0f // 定时器加速倍率 (16 倍速)
#define VIDEO_ACCELERATION 32.0f // 视频播放加速倍率 (32 倍速)

#pragma mark - 1. NSTimer 全局倒计时加速 (针对 P1/P2 落地页、H5 与“再逛45秒”倒计时)

static NSTimer *(*orig_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats)(Class self, SEL _cmd, NSTimeInterval ti, id aTarget, SEL aSelector, id userInfo, BOOL yesOrNo);
static NSTimer *my_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats(Class self, SEL _cmd, NSTimeInterval ti, id aTarget, SEL aSelector, id userInfo, BOOL yesOrNo) {
    // 凡是 0.5 秒 ~ 2.0 秒之间的周期性定时器 (典型的 1 秒倒计时)，全部缩短 16 倍
    if (yesOrNo && ti >= 0.5 && ti <= 2.5) {
        ti = ti / TIMER_ACCELERATION;
    }
    if (orig_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats) {
        return orig_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats(self, _cmd, ti, aTarget, aSelector, userInfo, yesOrNo);
    }
    return nil;
}

static NSTimer *(*orig_scheduledTimerWithTimeInterval_repeats_block)(Class self, SEL _cmd, NSTimeInterval ti, BOOL yesOrNo, void (^block)(NSTimer *));
static NSTimer *my_scheduledTimerWithTimeInterval_repeats_block(Class self, SEL _cmd, NSTimeInterval ti, BOOL yesOrNo, void (^block)(NSTimer *)) {
    if (yesOrNo && ti >= 0.5 && ti <= 2.5) {
        ti = ti / TIMER_ACCELERATION;
    }
    if (orig_scheduledTimerWithTimeInterval_repeats_block) {
        return orig_scheduledTimerWithTimeInterval_repeats_block(self, _cmd, ti, yesOrNo, block);
    }
    return nil;
}

#pragma mark - 2. 拦截第三方应用外跳 (阻止调起淘宝/京东等推广 App，直接欺骗已浏览)

static void (*orig_openURL_options_completionHandler)(id self, SEL _cmd, NSURL *url, NSDictionary *options, void (^completion)(BOOL success));
static void my_openURL_options_completionHandler(id self, SEL _cmd, NSURL *url, NSDictionary *options, void (^completion)(BOOL success)) {
    NSString *urlStr = url.absoluteString.lowercaseString;
    // 检测是否为常见推广 App 调起协议 (如 tbopen://, alipays://, pinduoduo://, snssdk:// 等)
    if ([urlStr containsString:@"tbopen"] || [urlStr containsString:@"alipay"] || 
        [urlStr containsString:@"pinduoduo"] || [urlStr containsString:@"snssdk"] ||
        [urlStr containsString:@"taobao"] || [urlStr containsString:@"jdmobile"]) {
        
        NSLog(@"[ETAlienSpeedup] 拦截到推广外链跳转: %@，阻止切出并直接伪装完成！", url);
        if (completion) {
            completion(YES); // 直接欺骗广告 SDK “跳转并成功打开了”
        }
        return;
    }
    
    if (orig_openURL_options_completionHandler) {
        orig_openURL_options_completionHandler(self, _cmd, url, options, completion);
    }
}

#pragma mark - 3. AVPlayer 全局视频 32 倍速快进 (针对纯视频广告)

static void (*orig_AVPlayer_setRate)(id self, SEL _cmd, float rate);
static void my_AVPlayer_setRate(id self, SEL _cmd, float rate) {
    if (rate > 0.0f) {
        rate = VIDEO_ACCELERATION;
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
        [self setRate:VIDEO_ACCELERATION];
    }
}

#pragma mark - 4. GroMore 广告页面弹窗自动关闭 Hook (自动点叉)

static void (*orig_didPlayFinish)(id self, SEL _cmd, id ad, id error);
static void my_didPlayFinish(id self, SEL _cmd, id ad, id error) {
    NSLog(@"[ETAlienSpeedup] 广告播放完毕，触发自动关闭逻辑...");
    if (orig_didPlayFinish) {
        orig_didPlayFinish(self, _cmd, ad, error);
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SEL closeSel = NSSelectorFromString(@"nativeExpressRewardedVideoAdDidClose:");
        if ([self respondsToSelector:closeSel]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [self performSelector:closeSel withObject:ad];
            #pragma clang diagnostic pop
        }
        
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        if (rootVC && rootVC != [UIApplication sharedApplication].keyWindow.rootViewController) {
            [rootVC dismissViewControllerAnimated:YES completion:nil];
            NSLog(@"[ETAlienSpeedup] 已自动 Dismiss 广告顶层控制器");
        }
    });
}

#pragma mark - 5. 专线节点提取与自动同步到 Documents/booster_nodes.txt

static void exportBoosterNodesFromAppGroup(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    // 获取 App Group 共享目录
    NSURL *groupURL = [fm containerURLForSecurityApplicationGroupIdentifier:@"group.etalien.booster"];
    if (!groupURL) {
        NSLog(@"[ETAlienSpeedup] 未能获取 group.etalien.booster 目录");
        return;
    }
    
    NSString *groupPath = groupURL.path;
    NSLog(@"[ETAlienSpeedup] 找到 App Group 目录: %@", groupPath);
    
    // 检查 App Group 下的配置文件
    NSArray *targetFiles = @[@"booster_config.json", @"region_list.json", @"auth_response.json"];
    NSMutableString *collectedContent = [NSMutableString string];
    [collectedContent appendFormat:@"===== 外星仔专线节点与配置提取 =====\n提取时间: %@\nAppGroup: %@\n\n", [NSDate date], groupPath];
    
    BOOL foundAny = NO;
    for (NSString *filename in targetFiles) {
        NSString *filePath = [groupPath stringByAppendingPathComponent:filename];
        if ([fm fileExistsAtPath:filePath]) {
            foundAny = YES;
            NSData *fileData = [NSData dataWithContentsOfFile:filePath];
            NSString *contentStr = [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
            [collectedContent appendFormat:@"\n----- 文件: %@ -----\n%@\n", filename, contentStr ?: @"[无法以UTF8解析]"];
        }
    }
    
    // 写入 Documents/booster_nodes.txt
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count > 0) {
        NSString *docPath = paths[0];
        NSString *outPath = [docPath stringByAppendingPathComponent:@"booster_nodes.txt"];
        if (foundAny) {
            [collectedContent writeToFile:outPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            NSLog(@"[ETAlienSpeedup] 专线节点已成功写入: %@", outPath);
        } else {
            NSString *emptyTip = [NSString stringWithFormat:@"AppGroup 中暂未生成节点文件，请先在 App 内点一次【开始加速】《荒野乱斗》！\n路径: %@", groupPath];
            [emptyTip writeToFile:outPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }
}

#pragma mark - 6. 插件入口与 Hook 初始化

static void swizzleClassMethod(Class cls, SEL origSel, IMP newImp, IMP *origImp) {
    if (!cls) return;
    Method m = class_getClassMethod(cls, origSel);
    if (!m) return;
    if (origImp) *origImp = method_getImplementation(m);
    method_setImplementation(m, newImp);
}

static void swizzleInstanceMethod(Class cls, SEL origSel, IMP newImp, IMP *origImp) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, origSel);
    if (!m) return;
    if (origImp) *origImp = method_getImplementation(m);
    method_setImplementation(m, newImp);
}

__attribute__((constructor)) static void initSpeedupPlugin(void) {
    NSLog(@"[ETAlienSpeedup v2.0] 插件已加载，正在注入全套加速与拦截机制...");
    
    // 1. Hook NSTimer (全平台 16 倍速倒计时加速，专治 45 秒、10 秒落地页浏览广告)
    Class timerClass = objc_getClass("NSTimer");
    if (timerClass) {
        SEL sel1 = @selector(scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:);
        swizzleClassMethod(timerClass, sel1, (IMP)my_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats, (IMP *)&orig_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats);
        
        SEL sel2 = @selector(scheduledTimerWithTimeInterval:repeats:block:);
        swizzleClassMethod(timerClass, sel2, (IMP)my_scheduledTimerWithTimeInterval_repeats_block, (IMP *)&orig_scheduledTimerWithTimeInterval_repeats_block);
        NSLog(@"[ETAlienSpeedup] NSTimer 16x 倒计时加速已启用！");
    }
    
    // 2. Hook UIApplication openURL (拦截调起淘宝等外链，防切出)
    Class appClass = objc_getClass("UIApplication");
    if (appClass) {
        SEL openSel = @selector(openURL:options:completionHandler:);
        swizzleInstanceMethod(appClass, openSel, (IMP)my_openURL_options_completionHandler, (IMP *)&orig_openURL_options_completionHandler);
        NSLog(@"[ETAlienSpeedup] UIApplication 推广外链拦截已启用！");
    }
    
    // 3. Hook AVPlayer (纯视频 32 倍速快进)
    Class avPlayerClass = objc_getClass("AVPlayer");
    if (avPlayerClass) {
        swizzleInstanceMethod(avPlayerClass, @selector(setRate:), (IMP)my_AVPlayer_setRate, (IMP *)&orig_AVPlayer_setRate);
        swizzleInstanceMethod(avPlayerClass, @selector(play), (IMP)my_AVPlayer_play, (IMP *)&orig_AVPlayer_play);
        NSLog(@"[ETAlienSpeedup] AVPlayer 32x 视频加速已启用！");
    }
    
    // 4. Hook FGMRewardVideoPage (完播自动关闭与跳过弹窗)
    Class fgmClass = objc_getClass("FGMRewardVideoPage");
    if (fgmClass) {
        SEL finishSel = NSSelectorFromString(@"nativeExpressRewardedVideoAdDidPlayFinish:didFailWithError:");
        swizzleInstanceMethod(fgmClass, finishSel, (IMP)my_didPlayFinish, (IMP *)&orig_didPlayFinish);
        NSLog(@"[ETAlienSpeedup] FGMRewardVideoPage 自动关闭已启用！");
    }
    
    // 5. 立即执行一次节点文件导出，并监听切后台/回前台事件持续同步
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exportBoosterNodesFromAppGroup();
    });
    
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        exportBoosterNodesFromAppGroup();
    }];
    
    NSLog(@"[ETAlienSpeedup v2.0] 全部功能加载完毕！");
}
