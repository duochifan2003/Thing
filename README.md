# 事件录

事件录是一个本地优先的人物事件档案工具，使用 Flutter 构建 Windows、Android 与 macOS 客户端。

## 功能

- 人物目录、事件时间线、全文搜索与多维筛选
- SQLite 本地档案，写入使用事务保护
- 兼容旧版 v1 JSON 导入和导出
- 人物、事件及关联关系的修订记录

## 开发

安装 Flutter 稳定版后：

```bash
cd flutter
flutter pub get
flutter run -d macos
```

验证：

```bash
cd flutter
flutter analyze
flutter test
flutter build macos --debug
```

Windows 与 Android 分别使用对应平台环境运行或构建。

## 项目结构

- `flutter/lib/`：Flutter 界面、档案模型与 SQLite 数据层
- `flutter/test/`：数据、迁移与界面测试
- `flutter/assets/`：应用图标与品牌资源
