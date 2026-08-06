# Repository Guidelines

## Project Structure

- `flutter/lib/` contains the Flutter UI, domain models, archive import/export, synchronization, and SQLite persistence.
- `flutter/test/` contains unit, repository, synchronization, update, and widget tests.
- `flutter/macos/`, `flutter/windows/`, and `flutter/android/` contain platform runners and native integrations; the macOS WidgetKit extension is under `flutter/macos/Widget/`.
- `flutter/assets/` stores bundled branding assets. `scripts/` contains macOS packaging helpers, and `.github/workflows/flutter.yml` defines CI.

## Build, Test, and Development Commands

Run Flutter commands from `flutter/`:

```bash
flutter pub get                              # install dependencies
dart format --output=none --set-exit-if-changed lib test
flutter analyze                              # static analysis
flutter test                                 # unit and widget tests
flutter run -d macos                         # run the macOS client
flutter build macos --debug                  # build macOS locally
flutter build windows --release              # build Windows (Windows/CI)
flutter build apk --debug                    # build Android
```

From the repository root, `sh scripts/package-macos-dmg.sh` builds the macOS release DMG; it requires `dmgbuild`.

## Coding Style & Naming

Use Dart null safety, two-space indentation, and `dart format`. Use `snake_case.dart` filenames, `PascalCase` types, and `camelCase` members and functions. Keep platform-specific code in its platform directory and do not edit generated Flutter files manually. Prefer the existing local-first SQLite and Archive v2 patterns before adding new persistence or serialization code.

## Testing Guidelines

Add focused tests in `flutter/test/` for behavior changes, especially storage, archive import/export, synchronization, validation, and user-visible workflows. Name files with the subject and `_test.dart` suffix, such as `archive_repository_test.dart`. The repository has no enforced coverage threshold; every change must pass formatting, analysis, and `flutter test`. The pre-commit hook runs `dart analyze` and `flutter test` when staged files touch `flutter/`.

## Commits and Pull Requests

Recent commits use short, imperative subjects, often in Chinese. Keep each commit focused; examples include `修复回收站删除` and `Add archive validation`. Pull requests should explain the user impact, link an issue when applicable, list verification commands, and include screenshots or recordings for UI changes. Report the OS, app version, and reproduction steps for bug fixes. Do not commit build outputs, local databases, JSON archives, sync folders, or secrets.

## Compatibility Notes

Preserve the existing bundle identifiers, database names, sync filenames, and WidgetKit identifiers unless a migration is included. Changes to release behavior should also be checked against the platform-specific build and packaging workflow.
