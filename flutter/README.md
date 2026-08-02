# Thing Flutter 客户端

这是 Thing 面向 macOS、Windows 和 Android 的 Flutter 客户端。完整的产品说明、安装教程、同步说明和开发命令请先阅读仓库根目录的 [README](../README.md)。

## 快速开始

建议使用 Flutter 3.44.8 或更高版本：

```bash
flutter pub get
flutter test
flutter run -d macos
```

构建其他平台：

```bash
flutter build macos --debug
flutter build windows --release
flutter build apk --debug
```

平台工程已包含在本目录中。macOS 与 Android 可以在 Mac 上运行；Windows 构建需要 Windows 环境或 GitHub Actions。
