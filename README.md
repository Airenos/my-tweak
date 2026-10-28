# ETAlienSpeedup

适用于外星仔加速器（iOS 移动端）的免看长广告与极速快进插件。

## 核心特性
- **视频 32 倍速快进**：Hook 底层 `AVPlayer`，将广告视频加速至 32 倍速播放，40 秒长广告在 1 秒内播放完毕并合规上报。
- **自动跳过弹窗与结算**：Hook `FGMRewardVideoPage`，视频播完自动触发 `didClose` 并关闭广告弹窗，无需手动点击右上角关闭按钮。
- **异常重试**：捕获奖励验证失败异常，自动向客户端补发成功回调。

## 构建与下载
本项目配置了 GitHub Actions 自动化构建工作流：
1. 每次提交代码后，GitHub Actions (macOS Runner) 会自动完成编译。
2. 前往 **Actions** -> 点击最新的 Workflow 运行记录 -> 在 **Artifacts** 中下载 `ETAlienSpeedup.dylib`。
3. 将下载的 `ETAlienSpeedup.dylib` 导入手机，使用 **TrollFools** 注入到外星仔加速器即可使用。
