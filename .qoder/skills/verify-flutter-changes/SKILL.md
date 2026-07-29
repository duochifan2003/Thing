---
name: verify-flutter-changes
description: 按 AGENTS.md 的验证流程依次运行 flutter pub get、flutter analyze、flutter test，并处理常见失败场景。适用于修改 flutter/lib 或 flutter/test 下的 Dart 代码后、提交前验证，或用户要求"验证改动"、"跑测试"、"检查代码"时。
---

# Verify Flutter Changes

对本仓库 Flutter 代码改动执行标准验证流程。所有命令必须在 `flutter/` 目录下运行。

## 验证步骤

按顺序执行，前一步失败时先处理失败再继续：

```
验证进度:
- [ ] Step 1: flutter pub get   （安装依赖）
- [ ] Step 2: flutter analyze   （静态检查）
- [ ] Step 3: flutter test      （单元与 Widget 测试）
```

**Step 1: 安装依赖**

```bash
cd flutter && flutter pub get
```

**Step 2: 静态检查**

```bash
cd flutter && flutter analyze
```

只有输出 `No issues found!` 才算通过。

**Step 3: 运行测试**

```bash
cd flutter && flutter test
```

所有测试通过（`All tests passed!`）才算验证完成。

改动涉及 macOS 平台代码或打包配置时，追加：

```bash
cd flutter && flutter build macos --debug
```

## 常见失败处理

| 失败现象 | 处理方式 |
|---|---|
| `pub get` 版本冲突（version solving failed） | 检查 `pubspec.yaml` 中新增依赖的版本约束是否与现有依赖兼容；不要盲目升级无关依赖 |
| `pub get` 网络超时 | 重试一次；仍失败则报告网络问题，不要修改镜像配置 |
| `analyze` 报 error | 必须修复后重新运行 Step 2；不要用 `// ignore:` 压制 |
| `analyze` 报 info/warning | 与本次改动相关的应修复；无关的历史问题记录并报告，不擅自大范围改动 |
| `flutter test` 个别用例失败 | 用 `flutter test test/<file>.dart` 单独复现，定位是改动引入还是测试需同步更新 |
| 测试因缺少 SQLite/平台通道报错 | 属于依赖平台环境的用例，报告具体报错，不要删除或跳过测试 |
| `flutter` 命令找不到 | 确认使用 Flutter stable；本仓库 `.tools/flutter/bin/flutter` 可作为备用路径 |

## 验证后

- 提交前运行 `dart format` 格式化改动文件。
- 报告结果时如实说明：每一步的通过/失败状态与关键输出；测试失败时附失败用例名称与报错，不要含糊表述为"基本通过"。

## 边界

- 本 Skill 只负责验证，不负责修复业务逻辑；修复由当前任务上下文决定。
- Android 需在真机或模拟器上验证，Windows 需在 Windows 或 CI 上验证，本 Skill 不覆盖这两个平台的运行时验证。
