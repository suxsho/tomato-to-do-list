# 番茄任务清单 · Tomato Timer

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)

一个支持 **WebDAV 云备份** 的多端番茄钟，用 Flutter 编写，可在 Windows / Android / Linux 上运行。

界面走的是「一个圆圈 + 一条水位」的极简路线：当前阶段一眼可见，不做花哨的动画堆砌。

<img width="1668" height="833" alt="image" src="https://github.com/user-attachments/assets/b8933aa1-ebc9-448c-843f-a103ff54b0e4" />

---

## 功能

**番茄钟**
- 专注 / 短休息 / 长休息三阶段自动流转，时长可自定义
- 长休息间隔（默认 4 个番茄）可调
- 结束有提示音、系统通知，窗口可闪烁提醒
- 专注结束后的「加时」正计时，不会粗暴打断你

**任务清单**
- 每个任务可预估番茄数，专注时自动归属到对应任务
- 长按排序、勾选完成
- 进行中的任务在卡片上有明确标识

<img width="1676" height="836" alt="ac9ff24b-f80e-4922-8e53-8eb6f703410a" src="https://github.com/user-attachments/assets/6ca58d4f-b237-46f3-81eb-344a41546944" />


**迷你小窗**
- 可切换到圆形小窗模式，贴边显示剩余时间，一直挂在前台
- 支持系统级屏幕常亮，防烧屏处理

<img width="210" height="210" alt="image" src="https://github.com/user-attachments/assets/e6216178-b96d-47d8-8514-763a6087460e" />


**统计**
- 日 / 周维度的番茄数量趋势图
- 按任务聚合的专注时长
- 每日自动重置，跨天不断档

**外观**
- 浅色 / 深色主题，统一在「我的 → 外观」切换
- 字体大小可调，界面按缩放系数整体适配，不会撑出滚动条

**WebDAV 云同步**
- 支持坚果云等任意标准 WebDAV 服务
- 完成番茄后自动上传，也可手动「上传备份 / 从云端恢复」
- 账号密码只保存在本机，不上传任何第三方服务器

---

## 下载

最新版本：[**v0.5.0**](https://github.com/suxsho/tomato-to-do-list/releases/latest)

| 平台 | 产物 | 获取方式 |
|---|---|---|
| Windows | `.zip`（解压即用，无需安装） | [Releases](https://github.com/suxsho/tomato-to-do-list/releases) |
| Android | `.apk` | [Releases](https://github.com/suxsho/tomato-to-do-list/releases) |
| Linux | `.AppImage` / `.tar.gz` | [Releases](https://github.com/suxsho/tomato-to-do-list/releases) |

| 文件 | 大小 | 说明 |
|---|---|---|
| `tomato_timer-0.5.0-windows-x64.zip` | 11.9 MB | 解压后运行 `tomato_timer.exe` |
| `tomato_timer-0.5.0-android.apk` | 51.5 MB | 支持 Android 5.0+，正式密钥签名 |
| `tomato_timer-0.5.0-linux-x86_64.AppImage` | 9.8 MB | 单文件，`chmod +x` 后双击运行 |
| `tomato_timer-0.5.0-linux-x64.tar.gz` | 9.7 MB | 解压即用，适合装到 `/opt` |

Linux 包由 GitHub Actions 在 Ubuntu 上自动构建，**不要**在 Windows 上试图直接构建 Linux 版（缺少 clang / cmake / ninja / GTK 开发库）。

想要自己构建的话，Windows / Android 可在本地执行 `build_windows.ps1` / `build_android.ps1`，详见[从源码构建](#从源码构建)。

### Linux 运行依赖

AppImage 不打包系统级的 GStreamer 和 zenity，绝大多数桌面发行版已自带。若提示音不响或文件选择框打不开，装一下：

```bash
# Debian / Ubuntu
sudo apt install libgstreamer1.0-0 gstreamer1.0-plugins-base zenity

# Fedora
sudo dnf install gstreamer1 gstreamer1-plugins-base zenity
```

---

## 从源码构建

前置：Flutter 3.47 或更高版本。

```bash
git clone https://github.com/suxsho/tomato-to-do-list.git
cd tomato-to-do-list/tomato_timer
flutter pub get
```

### Windows

```powershell
.\build_windows.ps1
# 产物：build\windows\x64\runner\Release\
```

### Android

```powershell
.\build_android.ps1                    # 构建 release APK
.\build_android.ps1 -Aab               # 构建 AAB（应用商店）
.\build_android.ps1 -Version 0.6.0+8   # 先写入版本号再构建
```

产物：`build\app\outputs\flutter-apk\app-release.apk`

> **签名说明**：正式版需要 `android/key.properties` 与对应 keystore（均不入库）。
> 仓库里没有这些文件，`build.gradle.kts` 会自动回退到 debug 签名以便编译通过。
> 自己用没问题，但**不能用于覆盖安装官方版**——签名不同，Android 会拒绝升级。

### Linux

需在 Linux 环境下构建：

```bash
flutter build linux --release
# 产物：build/linux/x64/release/bundle/
```

### 自动构建 Linux 包

推送 tag 或手动触发 GitHub Actions 即可：

```bash
git tag v0.5.0
git push github v0.5.0   # tag 会自动附加到 Release
```

工作流定义见 [`.github/workflows/linux.yml`](.github/workflows/linux.yml)，同时产出 AppImage 和 tar.gz 两种格式。

> Windows 与 Android 的包需本地构建后手动上传到 Release（GitHub 的 Windows runner 与 macOS runner
> 也可构建，但当前工作流只做 Linux，以控制构建时长）。

---

## 项目结构

```
.
├── .github/workflows/linux.yml   # Linux 自动构建（AppImage + tar.gz）
├── LICENSE                       # AGPL-3.0
├── README.md
├── tomato_timer/                 # Flutter 工程
│   ├── build_windows.ps1         # Windows 打包脚本
│   ├── build_android.ps1         # Android 打包脚本（APK / AAB）
│   ├── lib/
│   │   ├── app_state.dart        # 核心状态机：阶段流转、计时、记录、同步
│   │   ├── models.dart           # 任务 / 专注记录数据结构
│   │   ├── webdav.dart           # WebDAV 客户端（dart:io 实现，无三方依赖）
│   │   ├── mini_mode.dart        # 迷你圆形小窗
│   │   ├── theme.dart            # 配色与主题
│   │   └── screens/              # 主界面 / 计时 / 统计 / 我的 / 设置
│   ├── assets/                   # 图标与提示音
│   ├── linux/                    # Linux 平台（含 AppImage 打包骨架）
│   ├── windows/                  # Windows 平台
│   └── android/                  # Android 平台
└── _app_src/                     # 早期原型，仅作存档，不参与构建
```

## 技术栈

- **Flutter** / Dart 3.13+
- **provider** — 状态管理
- **shared_preferences** — 本地持久化
- **fl_chart** — 统计图表
- **window_manager** / **screen_retriever** — 桌面窗口控制
- **audioplayers** — 提示音
- **file_picker** / **path_provider** — 文件与路径

所有功能均为本地运行，除了你自己配置的 WebDAV 服务器，应用不连接任何远程服务。

---

## 许可证

本项目采用 **GNU Affero General Public License v3.0（AGPL-3.0）**，完整条款见 [LICENSE](LICENSE)。

你可以自由使用、修改和分发，但需遵守以下义务：

- **分发即开源**：分发本软件或其修改版时，必须一并提供完整的源代码，且同样以 AGPL-3.0 授权
- **网络服务同源**：即使不分发软件，仅通过网络向用户提供服务，也必须提供对应源代码
- **保留版权声明**：不得移除原作者版权信息

如果你希望在闭源商业产品中集成，或需要豁免 AGPL 的源码开放义务，请联系作者获取商业授权。

