1.叫我主人
2.避免使用“不是……而是……”等模板化对立句式；能并列说明时，不要强行制造二选一。
3.简单任务由主 Agent直接完成；复杂任务仅在有明确收益时按需调用子 Agent。子 Agent默认使用 GPT-5.6 Luna 这类低消耗模型，只有在任务难度、风险或失败情况确实需要时才升级模型。
4.避免使用 Emoji；需要表达语气时，可使用自然文字或标点代替。
5.日常交流中保持简短、自然，不要一次性倾倒大量内容或方案；仅在明确需要详细分析、对比或完整方案时再展开。

--- project-doc ---

# Repository Guidelines

## Project Structure

- `flutter/lib/` contains the shared Flutter interface, models, JSON migration, and SQLite repository.
- `flutter/test/` contains unit and widget tests.
- `flutter/assets/` contains application branding.
- `flutter/android/`, `flutter/macos/`, and `flutter/windows/` contain generated platform runners.

## Development and Verification

Use Flutter stable. Run commands from `flutter/`:

- `flutter pub get` installs dependencies.
- `flutter analyze` checks Dart code.
- `flutter test` runs unit and widget tests.
- `flutter run -d macos` starts the macOS client.
- `flutter build macos --debug` builds the macOS client.

Verify Android on a device or emulator. Verify Windows on Windows or CI.

## Style and Testing

Use `dart format` before submitting changes. Follow Dart conventions: two-space indentation, `PascalCase` types, `camelCase` members, and strict null safety. Add focused tests for storage, import/export, validations, and user-visible workflows.

## Commits

Keep commits scoped and imperative. State user impact and the verification commands in pull requests.

A pre-commit hook at `flutter/tool/git-hooks/pre-commit` runs `dart analyze` and `flutter test` whenever staged changes touch `flutter/`. Enable it once per clone: `ln -sf ../../flutter/tool/git-hooks/pre-commit .git/hooks/pre-commit`.
