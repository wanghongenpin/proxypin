[Flutter 3.32.0+ 找不到 flutter_gen？点此查看解决方法](#flutter-3320及以上版本-flutter_gen-使用说明)
# ProxyPin

[English](README.md) | 中文
## 开源免费抓包工具，支持Windows、Mac、Android、IOS、Linux 全平台系统

您可以使用它来拦截、检查和重写HTTP（S）流量，支持Flutter应用抓包，ProxyPin基于Flutter开发，UI美观易用。

## 核心特性

* 手机扫码连接：不用手动配置WiFi代理，包括配置同步。所有终端都可以互相扫码连接转发流量。
* 域名过滤：只拦截您所需要的流量，不拦截其他流量，避免干扰其他应用。
* 搜索：根据关键词、响应类型等多种条件搜索请求。
* 脚本：支持编写JavaScript脚本来处理请求或响应。
* 请求重写：支持重定向，支持替换请求或响应报文，也可以按规则修改请求或响应。
* 请求屏蔽：支持根据URL屏蔽请求，不让请求发送到服务器。
* 历史记录：自动保存抓包的流量数据，方便回溯查看。支持HAR格式导出与导入。
* 其他：收藏、工具箱、常用编码工具、以及二维码、正则等。

**Mac首次打开会提示不受信任开发者，需要到系统偏好设置-安全性与隐私-允许任何来源。**

国内下载地址：https://gitee.com/wanghongenpin/proxypin/releases

iOS AppStore 下载地址：https://apps.apple.com/app/proxypin/id6450932949

Android Google Play：https://play.google.com/store/apps/details?id=com.network.proxy

TG: https://t.me/proxypin_tg

**我们会持续完善功能和体验，优化UI。**

<img alt="image" width="580px" height="420px" src="https://github.com/user-attachments/assets/80f30d64-f2b5-473c-98f5-bae50b309278">.<img alt="image" height="500px" src="https://github.com/user-attachments/assets/3c5572b0-a9e5-497c-8b42-f935e836c164">

---

## Flutter 3.32.0及以上版本 flutter_gen 使用说明

[Flutter 破坏性变更：generate localizations source](https://docs.flutter.dev/release/breaking-changes/flutter-generate-i10n-source)

> **如在 Flutter 3.32.0 及以上版本打包时报 `package:flutter_gen` 找不到相关报错，可参考如下解决方法：**

本项目使用了 `flutter_gen` 进行本地化和资源生成。

- 如果你在 Flutter 3.32.0 及以上版本打包时报错（如“找不到 package:flutter_gen”），请在打包前执行：
  ```bash
  flutter config --no-explicit-package-dependencies
  ```
  打包完成后建议恢复默认配置：
  ```bash
  flutter config --explicit-package-dependencies
  ```

- 长期建议关注 Flutter 官方关于 `flutter_gen` 迁移和弃用的公告，并尽快迁移到新本地化方案。
---
