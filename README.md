# 番茄任务清单 · Tomato Timer

一个支持 **WebDAV 云备份** 的多端番茄钟，用 Flutter 编写，可在 Windows / Android / Linux 上运行。

界面走的是「一个圆圈 + 一条水位」的极简路线：当前阶段一眼可见，不做花哨的动画堆砌。

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

**迷你小窗**
- 可切换到圆形小窗模式，贴边显示剩余时间，一直挂在前台
- 支持系统级屏幕常亮，防烧屏处理

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

| 平台 | 产物 | 获取方式 |
|---|---|---|
| Linux | `.AppImage` / `.tar.gz` | [Releases](https://github.com/suxsho/tomato-to-do-list/releases) |
| Windows | `.exe` | 本地执行 `build_windows.ps1` |
| Android | `.apk` | 本地执行 `build_android.ps1` |

Linux 包由 GitHub Actions 在 Ubuntu 上自动构建，**不要**在 Windows 上试图直接构建 Linux 版（缺少 clang / cmake / ninja / GTK 开发库）。

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
cd tomato_timer
flutter pub get
```

```powershell
# Windows
.\build_windows.ps1
```

```powershell
# Android
.\build_android.ps1
```

```bash
# Linux（需在 Linux 环境下）
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

---

## 项目结构

```
.
├── .github/workflows/linux.yml   # Linux 自动构建
├── tomato_timer/                 # Flutter 工程
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

本项目尚未添加开源许可证文件。在补上之前，默认保留所有权利 —— 如需转载、二次分发或用于商业用途，请先联系作者。
