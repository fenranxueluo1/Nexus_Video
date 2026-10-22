# Nexus Video

基于 Flutter 的哔哩哔哩、YouTube、X（Twitter）与抖音媒体解析与归档工具。

支持 Windows、macOS、Linux、Android 和 iOS。

> 当前仓库只在 Windows 上完成过完整构建和运行验证；macOS/Linux 需要分别在对应系统上构建验证。

## 功能
支持下载的视频
- B 站视频、番剧、课程、收藏夹、合集、系列、创作者投稿与稍后再看
- YouTube 单视频、Shorts 与播放列表
- X 公开视频帖子
- 抖音公开视频，支持 `v.douyin.com` 分享短链
- 分片下载、断点续传、并发任务、限速和 HTTP/HTTPS 代理
- 视频/音频合并，字幕、弹幕、封面与 NFO 导出
- B 站扫码登录、软件内 YouTube/X/抖音登录和 Cookie 导入
- 路径模板、输出方案、任务日志和完成记录

## 平台支持

| 平台 | 下载 | 软件内登录 | 合并方式 | 说明 |
| --- | --- | --- | --- | --- |
| Windows 10/11 x64 | 完整 | B 站、YouTube、X、抖音 | FFmpeg | 已验证 |
| macOS 12+ | 完整（预期） | B 站、YouTube、X、抖音 | FFmpeg | 需在 macOS 上构建验证 |
| Linux | 完整（预期） | 仅 B 站扫码 | FFmpeg | 无 WebView 登录，需手动 Cookie |
| Android | B 站、X、抖音；YouTube 受限 | B 站、抖音 | MediaMuxer | 不支持 yt-dlp/Deno |
| iOS 15+ | B 站、X、抖音；YouTube 受限 | B 站、抖音 | AVFoundation | 不支持 yt-dlp/Deno |

移动端只能合并为 **MP4/M4A**，不支持 MKV、MP3、FLAC、字幕嵌入或封面嵌入。

## 使用流程

1. 打开软件，进入“解析链接”页。
2. 粘贴 B 站、YouTube、X 或抖音链接，点击解析。
3. 选择要下载的视频、清晰度和输出方案。
4. 点击“生成任务结果”，任务进入队列。
5. 在“任务”页查看进度、日志和输出文件。

常用设置：

- **保存位置**：所有任务和输出文件的根目录
- **输出方案**：容器、清晰度、编码、封面、字幕和 NFO
- **网络代理**：留空时自动检测系统代理和常见本机代理端口
- **账号**：B 站扫码，YouTube/X/抖音软件内登录

## Windows

### 直接使用

下载 `NexusDownload-Windows-x64.zip`，解压后运行 `nexus_video.exe`。

发布包已经内置：

- `ffmpeg/ffmpeg.exe`
- `tools/yt-dlp.exe`
- `tools/deno.exe`
- VC++ 运行库 DLL
- WebView2 安装引导 `redist/MicrosoftEdgeWebView2Setup.exe`

系统要求：

- Windows 10/11 x64
- 软件内登录依赖 Microsoft Edge WebView2 Runtime；如果登录窗口空白，运行 `redist/MicrosoftEdgeWebView2Setup.exe`

### 源码构建

需要 Flutter SDK、Visual Studio C++ 桌面开发组件和一个可用的 NuGet CLI。

```powershell
flutter pub get
flutter build windows --release
```

### 打包

```powershell
powershell -ExecutionPolicy Bypass -File scripts\package_windows.ps1
```

打包脚本会下载或复用 FFmpeg、yt-dlp、Deno，并生成 `dist/NexusDownload-Windows-x64.zip`。

签名说明见下方“Windows 代码签名”。

## macOS

### 直接使用

在 macOS 上构建或使用打包脚本生成 `.app`：

```bash
chmod +x scripts/package_macos.sh
./scripts/package_macos.sh
```

如果软件提示无法验证开发者，右键 App 选择“打开”，或执行：

```bash
xattr -dr com.apple.quarantine nexus_video.app
```

需要：

- macOS 12+
- 软件内登录依赖系统 WKWebView
- FFmpeg；如果使用 Homebrew 版本，打包时需要 `dylibbundler`，也可以通过 `FFMPEG_PATH` 指定静态 ffmpeg

### 源码构建

需要 Xcode、CocoaPods 和 Flutter：

```bash
flutter pub get
cd macos && pod install && cd ..
flutter build macos --release
```

## Linux

### 直接使用

```bash
chmod +x scripts/package_linux.sh
./scripts/package_linux.sh
```

生成 `dist/NexusDownload-Linux-<arch>.tar.gz`，解压后运行 `nexus_video`。

Linux 仍需要系统提供 GTK3、GLib、libstdc++ 等 Flutter Linux 运行库。Ubuntu/Debian 可安装：

```bash
sudo apt install libgtk-3-0 libblkid1 liblzma5
```

### 源码构建

```bash
flutter pub get
flutter build linux --release
```

Linux 没有 `flutter_inappwebview` 实现，因此不显示 YouTube/X/抖音软件内登录按钮。YouTube 可在设置中手动选择 `cookies.txt`；X、抖音只能使用公开内容。

## Android

### 构建与安装

```bash
flutter pub get
flutter build apk --release
```

APK 路径：

```text
build/app/outputs/flutter-apk/app-release.apk
```

安装时按系统提示允许“安装未知来源软件”。

### 使用说明

- B 站、X、抖音公开视频可用
- 合并使用系统 MediaMuxer，只支持 MP4/M4A
- 默认保存到软件专属目录；设置页可以恢复默认目录
- 抖音支持软件内登录；YouTube/X 登录入口不显示
- 无法运行 yt-dlp/Deno，YouTube 使用纯 Dart 提取，部分视频会因为签名或机器人校验失败
- 可在设置中手动填写 HTTP/HTTPS 代理

## iOS

### 构建

需要在 macOS + Xcode 上操作：

```bash
flutter pub get
cd ios && pod install && cd ..
flutter build ios --release
```

也可以在 Xcode 中打开 `ios/Runner.xcworkspace`，配置 Team、Bundle ID 和签名后归档。

### 使用说明

- iOS 15+
- 合并使用 AVFoundation，只支持 MP4/M4A
- B 站、X、抖音公开视频可用
- 抖音支持软件内登录；YouTube/X 登录入口不显示
- 不能运行 yt-dlp/Deno，YouTube 能力受限
- 支持软件专属目录和系统文件导出

## 代理

设置中的代理字段留空时，软件会自动：

- 读取系统代理（Windows 注册表、macOS `scutil`、Linux 环境变量）
- 探测常见本机代理端口：`7897`、`7890`、`1080`、`10808` 等

也可以手动填写：

```text
http://127.0.0.1:7897
```

软件只使用代理，不会修改系统代理。软件内登录 WebView 使用系统代理；如果代理软件只开放本地端口但没有设置系统代理，登录窗口可能不经过该端口。

## YouTube 说明

桌面端优先使用 yt-dlp：

- 首次解析时从 GitHub 下载 `yt-dlp` 到软件支持目录，并校验 SHA-256
- 首次解析时下载 Deno，用于解决 YouTube 签名和 `n` challenge
- 也可以手动把 `yt-dlp.exe`/`yt-dlp` 和 `deno.exe`/`deno` 放入软件目录、`tools/`、`bin/` 或 `PATH`

YouTube 返回机器人校验时，在“账号”页登录 YouTube，或在设置中选择浏览器导出的 Netscape `cookies.txt`。

## 抖音说明

- 使用纯 Dart 请求公开移动端接口，桌面和移动端都可用
- 支持 `v.douyin.com` 分享短链、`modal_id` 和完整视频链接
- 图文作品不支持
- 被抖音标记为付费/受限（`base_charge_limit_source`）的作品无法下载
- 登录抖音后，Cookie 会用于详情接口和媒体请求；不会绕过付费权限

## Windows 代码签名

打包脚本支持在压缩前签名 `nexus_video.exe`：

```powershell
# 证书已安装到 CurrentUser\My，使用指纹
.\scripts\package_windows.ps1 -CertificateThumbprint "THUMBPRINT"

# 或使用 PFX（不建议在共享终端使用明文密码）
.\scripts\package_windows.ps1 -PfxPath "cert.pfx" -PfxPassword "password"
```

脚本会使用 `signtool` 做 SHA-256 签名和 RFC3161 时间戳，并执行 `verify /pa`。

ZIP 本身不能用 Authenticode 签名；需要签名的是 `nexus_video.exe` 或最终安装器。

## 第三方项目与许可证

### 运行时工具

| 项目 | 用途 | 许可证 |
| --- | --- | --- |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | YouTube 解析和格式提取 | Unlicense |
| [Deno](https://github.com/denoland/deno) | 执行 YouTube 播放器 JS 挑战 | MIT |
| [FFmpeg](https://ffmpeg.org/) | 桌面端音视频合并和后处理 | GPL/LGPL，取决于构建 |
| Microsoft Edge WebView2 Runtime | 软件内登录网页容器 | Microsoft 许可 |
| Microsoft Visual C++ Runtime | Windows 运行库 | Microsoft 许可 |

### Flutter 依赖

| 包 | 用途 | 许可证 |
| --- | --- | --- |
| [flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview) | 软件内登录 WebView | Apache-2.0 |
| [youtube_explode_dart](https://pub.dev/packages/youtube_explode_dart) | 移动端 YouTube 元数据与流提取 | MIT |
| [archive](https://pub.dev/packages/archive) | ZIP 解压 | MIT |
| [crypto](https://pub.dev/packages/crypto) | SHA-256 校验 | BSD-3-Clause |
| [file_selector](https://pub.dev/packages/file_selector) | 文件和目录选择 | BSD-3-Clause |
| [http](https://pub.dev/packages/http) | HTTP 请求 | BSD-3-Clause |
| [intl](https://pub.dev/packages/intl) | 国际化格式化 | BSD-3-Clause |
| [path](https://pub.dev/packages/path) | 路径处理 | BSD-3-Clause |
| [path_provider](https://pub.dev/packages/path_provider) | 软件目录 | BSD-3-Clause |
| [qr_flutter](https://pub.dev/packages/qr_flutter) | B 站登录二维码 | BSD-3-Clause |
| [xml](https://pub.dev/packages/xml) | XML/字幕处理 | MIT |
| [cupertino_icons](https://pub.dev/packages/cupertino_icons) | 图标资源 | MIT |

`third_party/flutter_inappwebview_android` 是 Apache-2.0 的本地兼容补丁，用于适配 AGP 9，不改变上游功能。

### 网络接口

- B 站公开 Web API
- YouTube 通过 yt-dlp 或 `youtube_explode_dart`
- X 通过 fxtwitter 和 Twitter syndication 公开接口
- 抖音公开移动端接口

这些接口都不是本项目官方合作接口，可能随平台策略调整而失效。请遵守各平台的服务条款，只下载你有权保存的内容。

## 构建脚本

```text
scripts/package_windows.ps1
scripts/package_macos.sh
scripts/package_linux.sh
```

macOS/Linux 打包脚本必须在对应系统上执行，不能从 Windows 交叉生成。

## 许可证

本项目使用 **GNU General Public License v3.0**，详见 [LICENSE](LICENSE)。

分发包含 FFmpeg 的二进制包时，需要同时遵守所使用 FFmpeg 构建的 GPL/LGPL 条款；yt-dlp 和 Deno 分别遵循 Unlicense 与 MIT。
