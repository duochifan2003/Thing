# Thing

[![Flutter checks](https://github.com/duochifan2003/Thing/actions/workflows/flutter.yml/badge.svg?branch=main)](https://github.com/duochifan2003/Thing/actions/workflows/flutter.yml)
[![Latest release](https://img.shields.io/github/v/release/duochifan2003/Thing?display_name=tag)](https://github.com/duochifan2003/Thing/releases/latest)

Thing 是一个本地优先的人物与事件档案工具。它适合整理人物、时间线、地点、提醒、标签和事件之间的关系，支持 macOS、Windows 与 Android 客户端。

档案默认保存在当前设备。你可以使用 JSON 备份，或将一个同步文件夹交给 Syncthing、Nextcloud Desktop 等自托管工具，在多台设备之间同步档案。

## 功能

- 人物目录与事件时间线，支持搜索、筛选和事件状态
- 人物与事件分别维护标签，支持自定义标签
- 年份、月份、具体日期和起止区间四种时间精度
- 地点、人物角色、事件前序关系、提醒和修订记录
- SQLite 本地工作数据库，写入使用事务保护
- Archive v2 JSON 导入、导出和导入预检，兼容旧版 v1 档案
- 设置页中的主题模式、主色、默认时间精度和数据管理
- 回收站、恢复、保留期限和跨设备删除标记
- 通过同步文件夹进行三方合并和冲突选择
- macOS WidgetKit 小组件，Windows 不依赖小组件
- 从 GitHub Releases 检查并安装 macOS、Windows 更新

## 下载

前往 [Releases](https://github.com/duochifan2003/Thing/releases/latest) 下载最新版本。

| 平台 | 发布包 | 说明 |
| --- | --- | --- |
| macOS | `Thing-macOS-*.dmg` | 打开 DMG 后将 Thing 拖入“应用程序” |
| Windows | `Thing-windows-*.zip` | 解压后运行 `Thing.exe` |
| Android | 源码构建 | 当前仓库提供 Android 工程，暂未提供公开 APK |

## macOS 安装

1. 在最新 Release 下载 macOS DMG。
2. 打开 DMG，将 `Thing.app` 拖到“应用程序”文件夹。
3. 第一次打开时，如果 macOS 提示无法验证开发者，请在 Finder 中右键 Thing，选择“打开”，再确认打开；也可以到“系统设置 → 隐私与安全性”允许本次启动。
4. 打开应用后，在“设置 → 应用更新”中检查后续版本。

应用的 Bundle ID 保持为 `local.munch.eventatlas`，用于保留已有数据和 macOS 小组件关联。应用显示名称改为 Thing，旧版本升级时不需要手动搬运数据库。

## Windows 安装

1. 在最新 Release 下载 Windows ZIP。
2. 将 ZIP 解压到一个有写入权限的文件夹，例如 `D:\Apps\Thing`。
3. 运行解压目录中的 `Thing.exe`。建议为它创建桌面快捷方式。
4. 如果 Windows SmartScreen 显示警告，确认下载来源为本仓库 Release 后点击“更多信息 → 仍要运行”。
5. 后续版本可以在“设置 → 应用更新”中检查并安装。

Windows 包是免安装目录包，删除整个目录会删除程序文件；档案数据由应用单独保存，不要把 SQLite 数据库文件直接放进同步文件夹。

## 应用内更新

打开“设置 → 应用更新 → 检查更新”。Thing 会从公开的 GitHub Release 读取最新版本，并按当前系统选择 DMG 或 Windows ZIP。

更新检查需要网络连接。macOS 版本需要把应用放在可写位置，Windows 版本需要对安装目录有写入权限。下载和替换期间请不要强制退出应用。

如果检查失败，可以先确认网络和系统代理，再打开 [Releases](https://github.com/duochifan2003/Thing/releases) 手动下载安装包。

## Syncthing 跨设备同步

Thing 本身不提供账号、服务器或后台同步服务。同步由一个普通文件夹和 Syncthing、Nextcloud Desktop 等自托管工具完成。

### 配置步骤

1. 在 macOS 与 Windows 上安装并启动 Syncthing。
2. 在两台设备中添加对方设备，并共享同一个同步文件夹，例如 macOS 使用 `~/ThingSync`，Windows 使用 `D:\ThingSync`。
3. 在 Thing 中打开“设置 → 自托管同步与回收站”。
4. 打开“启用同步”，选择刚才的同步文件夹。
5. 首次同步时点击“立即同步”。如果两边都有档案，先查看合并预览；出现同一条记录的双端修改时，在冲突面板选择保留本机或同步文件版本。

同步文件名为 `person-event-atlas.sync.json`，这是为了兼容已有设备，改名为 Thing 后仍继续使用。同步文件包含人物、事件、地点、状态、提醒、标签、修订记录、回收站和删除标记；主题、主色、默认时间精度和同步目录只保存在本机。

删除人物或事件会先进入回收站，并在同步文件中留下删除标记，避免旧设备把已删除记录重新带回来。标签仍按当前逻辑立即移除。回收站保留期限可在设置中选择立即、7 天、30 天、90 天、半年或一年。

### 同步注意事项

- 只同步 Thing 生成的同步文件，不要把 SQLite 数据库、`-wal` 或 `-shm` 文件放入 Syncthing。
- 两台设备应让 Thing 使用同一个同步文件夹根目录，不要分别选择同步文件里的子目录。
- 同步文件是普通 JSON 文本。请使用设备磁盘加密、Syncthing 访问控制或自托管服务权限保护它。
- 同步目录变化会自动触发同步；也可以在设置中手动点击“立即同步”。

## 备份、导入与导出

打开“设置 → 数据管理”：

- “导出 JSON”保存一个 `Archive v2` 档案备份。
- “导入 JSON”会先预检新增、重复和冲突记录，确认后用导入档案替换当前本地资料。
- 主题、主色、默认时间精度、同步目录和其他本机偏好不会写入档案。
- 导入前建议先导出一次当前档案；导入操作不会删除原文件，但会替换当前数据库内容。

导出的 JSON 可用于手动备份、迁移和版本回退。当前格式兼容旧版 `Archive v1` 档案。

## 数据与隐私

- Thing 没有登录账号，也不会把档案自动上传到 Thing 的服务器。
- 人物、事件、设置和修订记录保存在本机 SQLite 数据库中。
- 只有在你主动启用同步并选择目录后，档案才会写入同步文件夹。
- GitHub 仓库只存放源代码和发布包，不包含你的本地数据库、JSON 档案或同步目录内容。
- 包标识和数据文件名保持稳定，应用改名不会主动删除或迁移你的既有数据。

## 常见问题

### macOS 提示应用来自身份不明的开发者

这是未经过 App Store 分发或 Apple 公证时的系统提示。确认 DMG 来自本仓库后，在 Finder 中右键应用选择“打开”，或在“系统设置 → 隐私与安全性”允许启动。

### Windows 提示无法运行或 SmartScreen 警告

先确认 ZIP 已完整解压，不要直接在压缩包预览器中运行。确认来源后，在 SmartScreen 窗口选择“更多信息 → 仍要运行”。

### 应用内检查更新失败

检查网络是否能访问 `github.com`，确认使用的是最新公开版本。如果当前版本很旧，直接从 [最新 Release](https://github.com/duochifan2003/Thing/releases/latest) 手动安装一次即可。

### 同步后另一台设备没有变化

先确认 Syncthing 两端都显示文件夹已共享并完成传输，再在 Thing 设置中点击“立即同步”。如果两端都编辑了同一条记录，应用会停在冲突面板，必须选择一个版本后才会继续合并。

### 找不到旧数据

请先退出应用并确认打开的是同一个操作系统用户。应用改名不会改变 Bundle ID、数据库文件名或同步文件名；不要通过删除应用目录来清理问题，先使用“导出 JSON”保存备份。

## 开发

### 环境要求

- Flutter stable，建议 Flutter 3.44.8 或更高版本
- Dart SDK 3.8 或更高版本
- macOS 构建需要 Xcode 和 macOS SDK
- Windows 构建需要 Windows、Visual Studio C++ 工具链和 Flutter Windows 支持
- Android 构建需要 Android SDK 和对应的 Gradle 环境

### 获取并运行

```bash
git clone https://github.com/duochifan2003/Thing.git
cd Thing/flutter
flutter pub get
flutter run -d macos
```

Windows 和 Android 使用对应设备运行：

```bash
flutter devices
flutter run -d windows
flutter run -d android
```

### 项目结构

- `flutter/lib/`：Flutter 界面、模型、JSON 迁移、同步和 SQLite 数据层
- `flutter/test/`：数据、导入导出、同步、更新和 Widget 测试
- `flutter/macos/`：macOS Runner 与 WidgetKit 小组件
- `flutter/windows/`：Windows Runner
- `flutter/android/`：Android 工程
- `flutter/assets/`：图标与品牌资源
- `.github/workflows/flutter.yml`：格式检查、分析、测试和 Windows 构建 CI

### 验证

在 `flutter/` 目录执行：

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build macos --debug
flutter build windows --release
```

Android 请在实际设备或模拟器上额外验证：

```bash
flutter build apk --debug
```

## 发布规则

- Flutter 版本写在 `flutter/pubspec.yaml`，格式为 `主版本.次版本.修订号+构建号`。
- GitHub Release 使用 `v主版本.次版本.修订号` 标签，例如 `v0.1.6`。
- `main` 是唯一有效代码来源，合并前必须通过 `test` 和 Windows 构建检查。
- macOS DMG 在 macOS 环境构建；Windows ZIP 由 GitHub Actions Windows runner 构建并上传到 Release。
- 重命名只影响仓库路径和用户可见名称，包标识、数据库、同步文件和 Widget 标识继续保持兼容。

## 参与贡献

欢迎通过 [Issue](https://github.com/duochifan2003/Thing/issues) 报告问题，或提交 Pull Request。提交前请在 `flutter/` 目录运行格式检查、分析和测试，并在问题描述中说明操作系统、应用版本和复现步骤。

## 许可证

当前仓库尚未附带 `LICENSE` 文件。代码默认受作者版权保护；如果需要二次分发、商用或基于本项目发布衍生版本，请先联系作者并补充明确的许可证。
