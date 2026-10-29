/**
 * ETAlienSpeedup.m v2.1 - 外星仔加速器全能强化插件
 * 
 * 核心升级与修复:
 * 1. [新增] 自动模拟下滑浏览 (Auto-Scroll Anti-AFK):
 *    - 破解 P2 中“需要下滑浏览更多才能领取奖励哦”的挂机检测！
 *    - 后台定时对广告页面中的 UIScrollView / WKWebView 触发轻微滚动，彻底解除倒计时暂停！
 * 2. [移除] 移除对 openURL 的强制拦截，避免出现 P1“返回继续浏览”的未达标提示。
 * 3. [保留] NSTimer 全局 16 倍速倒计时加速 (45 秒、15 秒倒计时秒跳)。
 * 4. [保留] AVPlayer 32 倍速视频快进。
 * 5. [保留] 广告播完自动关闭页面 (FGMRewardVideoPage)。
 * 6. [增强] 专线节点提取: 双重扫描 AppGroup (group.etalien.booster) 并备份到 Documents/booster_nodes.txt。
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#define TIMER_ACCELERATION 16.0f // 定时器加速倍率
#define VIDEO_ACCELERATION 32.0f // 视频播放加速倍率

#pragma mark - 1. 自动模拟下滑浏览 (破解 P2 的“需要下滑浏览更多才能领奖”防挂机检测)

static void nudgeAllScrollViews(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *sv = (UIScrollView *)view;
        // 只有当能够向上滚动时进行微量位移，触发滑动事件通知
        CGPoint offset = sv.contentOffset;
        offset.y += 2.0;
        sv.contentOffset = offset;
        
        // 主动通知 delegate 发生了滑动
        if ([sv.delegate respondsToSelector:@selector(scrollViewDidScroll:)]) {
            [sv.delegate scrollViewDidScroll:sv];
        }
    }
    for (UIView *subview in view.subviews) {
        nudgeAllScrollViews(subview);
    }
}

// 后台循环检测：如果当前有弹出的广告界面，每隔 1 秒自动模拟一次下滑手势
static void startAutoScrollWatcher(void) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (1) {
            [NSThread sleepForTimeInterval:1.0];
            dispatch_async(dispatch_get_main_queue(), ^{
                UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
                UIViewController *topVC = root;
                while (topVC.presentedViewController) {
                    topVC = topVC.presentedViewController;
                }
                // 如果当前顶层存在非主界面的浮层/广告页
                if (topVC && topVC != root) {
                    nudgeAllScrollViews(topVC.view);
                }
            });
        }
    });
}

#pragma mark - 2. NSTimer 全局倒计时加速 (针对“再逛45秒”等所有倒计时)

static NSTimer *(*orig_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats)(Class self, SEL _cmd, NSTimeInterval ti, id aTarget, SEL aSelector, id userInfo, BOOL yesOrNo);
static NSTimer *my_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats(Class self, SEL _cmd, NSTimeInterval ti, id aTarget, SEL aSelector, id userInfo, BOOL yesOrNo) {
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
    NSLog(@"[ETAlienSpeedup] 广告播放完毕，准备自动关闭...");
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

#pragma mark - 5. 专线节点提取: 扫描 AppGroup (group.etalien.booster) 并备份到 Documents/

static void exportBoosterNodesFromAppGroup(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // 方式 1: 通过标准 containerURL 获取
    NSURL *groupURL = [fm containerURLForSecurityApplicationGroupIdentifier:@"group.etalien.booster"];
    NSString *groupPath = groupURL ? groupURL.path : nil;
    
    // 方式 2: 如果标准 API 未获取到，直接扫描越狱/巨魔 AppGroup 物理路径
    if (!groupPath || ![fm fileExistsAtPath:groupPath]) {
        NSString *baseAppGroup = @"/var/mobile/Containers/Shared/AppGroup";
        NSArray *subdirs = [fm contentsOfDirectoryAtPath:baseAppGroup error:nil];
        for (NSString *sub in subdirs) {
            NSString *candidate = [baseAppGroup stringByAppendingPathComponent:sub];
            NSString *metaFile = [candidate stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            if ([fm fileExistsAtPath:metaFile]) {
                NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:metaFile];
                if ([dict[@"MCMMetadataIdentifier"] isEqualToString:@"group.etalien.booster"]) {
                    groupPath = candidate;
                    break;
                }
            }
        }
    }
    
    if (!groupPath) {
        NSLog(@"[ETAlienSpeedup] 暂未定位到 group.etalien.booster 目录");
        return;
    }
    
    NSLog(@"[ETAlienSpeedup] 找到 App Group 目录: %@", groupPath);
    
    NSArray *targetFiles = @[@"booster_config.json", @"region_list.json", @"auth_response.json", @"remote_config.json"];
    NSMutableString *collected = [NSMutableString string];
    [collected appendFormat:@"===== 外星仔专线节点与配置提取 =====\n提取时间: %@\n物理路径: %@\n\n", [NSDate date], groupPath];
    
    BOOL foundAny = NO;
    for (NSString *filename in targetFiles) {
        NSString *filePath = [groupPath stringByAppendingPathComponent:filename];
        if ([fm fileExistsAtPath:filePath]) {
            foundAny = YES;
            NSData *data = [NSData dataWithContentsOfFile:filePath];
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [collected appendFormat:@"\n========== 文件: %@ ==========\n%@\n", filename, str ?: @"[二进制或非UTF8数据]"];
        }
    }
    
    // 写入 Documents/booster_nodes.txt
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count > 0) {
        NSString *outPath = [paths[0] stringByAppendingPathComponent:@"booster_nodes.txt"];
        if (foundAny) {
            [collected writeToFile:outPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            NSLog(@"[ETAlienSpeedup] 专线节点已同步写入: %@", outPath);
        } else {
            NSString *tip = [NSString stringWithFormat:@"AppGroup 中暂未生成节点文件，请先在 App 内点一次【开始加速】《荒野乱斗》！\nAppGroup路径: %@", groupPath];
            [tip writeToFile:outPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
    NSLog(@"[ETAlienSpeedup v2.1] 插件加载中...");
    
    // 1. 启用自动模拟滑动防挂机侦测 (破解“需要下滑浏览更多”)
    startAutoScrollWatcher();
    NSLog(@"[ETAlienSpeedup] 自动模拟下滑防挂机看门狗已启动！");
    
    // 2. Hook NSTimer (全平台 16 倍速倒计时加速)
    Class timerClass = objc_getClass("NSTimer");
    if (timerClass) {
        SEL sel1 = @selector(scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:);
        swizzleClassMethod(timerClass, sel1, (IMP)my_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats, (IMP *)&orig_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats);
        
        SEL sel2 = @selector(scheduledTimerWithTimeInterval:repeats:block:);
        swizzleClassMethod(timerClass, sel2, (IMP)my_scheduledTimerWithTimeInterval_repeats_block, (IMP *)&orig_scheduledTimerWithTimeInterval_repeats_block);
        NSLog(@"[ETAlienSpeedup] NSTimer 16x 倒计时加速已启用！");
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
    
    // 5. 定时与前后台事件同步专线节点文件
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exportBoosterNodesFromAppGroup();
    });
    
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        exportBoosterNodesFromAppGroup();
    }];
    
    NSLog(@"[ETAlienSpeedup v2.1] 全部功能初始化完毕！");
}
