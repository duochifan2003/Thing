# 事件录 Flutter 版

这是面向 Windows、Android、macOS 的原生 Flutter 重写版本。当前版本使用 SQLite 保存人物、事件、关联关系与修订历史，支持筛选、JSON 导入预检和兼容旧 Web 版的 JSON 备份。现有 Web/PWA 版本仍保留在仓库根目录，迁移期间不会被覆盖。

先安装 Flutter 3.44.8 或更高版本，然后在本目录执行：

```bash
flutter pub get
flutter test
flutter run -d macos
```

平台工程已包含在本目录中。macOS 与 Android 可以在 Mac 上运行；Windows 安装包需要 Windows 环境或 CI 构建。
