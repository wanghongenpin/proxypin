[Flutter 3.32.0+ flutter_gen not found? Click here for solution](#flutter-3320-and-above-flutter_gen-usage-note)
# ProxyPin

English | [中文](README_CN.md)
## Open source free traffic capture HTTP(S)，Support Windows、Mac、Android、IOS、Linux Full platform system

You can use it to intercept, inspect & rewrite HTTP(S) traffic, Support capturing Flutter app traffic, ProxyPin is based on Flutter develop, and the UI is beautiful
and easy to use.

## Features
* Mobile scan code connection: no need to manually configure WiFi proxy, including configuration synchronization. All terminals can scan codes to connect and forward traffic to each other.
* Domain name filtering: Only intercept the traffic you need, and do not intercept other traffic to avoid interference with other applications.
* Search: Search requests according to keywords, response types and other conditions
* Script: Support writing JavaScript scripts to process requests or responses.
* Request rewrite: Support redirection, support replacement of request or response message, and can also modify request or response according to the increase.
* Request blocking: Support blocking requests according to URL, and do not send requests to the server.
* History: Automatically save the captured traffic data for easy backtracking and viewing. Support HAR format export and import.
* Others: Favorites, toolbox, common encoding tools, as well as QR codes, regular expressions, etc.

**Mac will prompt untrusted developers when first opened, you need to go to System Preferences-Security & Privacy-Allow any source.**

Download： https://github.com/wanghongenpin/proxypin/releases

iOS App Store：https://apps.apple.com/app/proxypin/id6450932949

Android Google Play：https://play.google.com/store/apps/details?id=com.network.proxy

TG: https://t.me/proxypin_en

**We will continue to improve the features and experience, as well as optimize the UI.**

<img alt="image"  width="580px" height="420px"  src="https://github.com/user-attachments/assets/6c1345ab-c95c-415d-ac59-470c764b59a2">.<img alt="image"  height="500px" src="https://github.com/user-attachments/assets/3c5572b0-a9e5-497c-8b42-f935e836c164">

---

## Flutter 3.32.0 and Above: flutter_gen Usage Note

[Flutter Breaking Change: generate localizations source](https://docs.flutter.dev/release/breaking-changes/flutter-generate-i10n-source)

> **If you encounter build errors related to `package:flutter_gen` when using Flutter 3.32.0 or later, please follow the steps below:**

This project uses `flutter_gen` for localization and resource generation.

- If you see build errors (such as “package:flutter_gen not found”) with Flutter 3.32.0 and above, please run before building:
  ```bash
  flutter config --no-explicit-package-dependencies
  ```
  After building, it is recommended to restore the default config:
  ```bash
  flutter config --explicit-package-dependencies
  ```

- For long-term compatibility, please follow Flutter's official announcements regarding `flutter_gen` migration and consider moving to the new localization solution as soon as possible.
---
