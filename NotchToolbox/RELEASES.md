# EasyNotch 发布渠道

| 渠道 | Xcode Scheme | 产物 | Bundle ID | 1.0.5 版本 |
| --- | --- | --- | --- | --- |
| 官网分发 | `NotchToolbox` | `EasyNotch.app` / `EasyNotch-1.0.5.dmg` | `com.luojie.NotchToolbox` | `1.0.5 (6)` |
| Mac App Store | `EasyNotchAppStore` | `EasyNotchAppStore.app` / `.pkg` | `com.luojie.NotchToolbox.appstore` | `1.0.5 (7)` |

两个渠道共享功能代码（包括刘海展开、收起与 Hover 动效），但签名、沙盒能力、音乐播放器能力和交付方式各自独立。

## 发版规则

1. 面向用户的功能或修复发布时，两个渠道的 `MARKETING_VERSION` 必须同步递增。
2. 每个渠道独立递增自己的 `CURRENT_PROJECT_VERSION`，不可为了保持一致而回退或复用 build 号。
3. 官网分发包通过 `Scripts/release.sh` 归档、Developer ID 签名、公证并生成 DMG；完成 GitHub Release 后，再发布官网中指向该 DMG 的链接。
4. Mac App Store 通过 `EasyNotchAppStore` scheme 归档，并使用 `ExportOptions-AppStore.plist` 导出/上传；上传前执行 `Scripts/validate-app-store-bundle.sh`。
5. 每次改动共享的刘海交互动效，两个 Release 都必须构建与验收；本次 1.0.5 即遵循该规则。
