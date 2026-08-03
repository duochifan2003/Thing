import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:person_event_atlas/app_update.dart';

void main() {
  test(
    'reads the latest GitHub release and selects a Windows package',
    () async {
      Uri? requested;
      final service = AppUpdateService(
        currentVersion: '0.1.4',
        operatingSystem: 'windows',
        fetchJson: (uri) async {
          requested = uri;
          return jsonEncode(_releaseJson());
        },
      );

      final release = await service.checkForUpdate();

      expect(requested?.host, 'api.github.com');
      expect(release?.version, '0.1.5');
      expect(release?.assetFor('windows')?.name, 'Thing-windows.zip');
    },
  );

  test('selects only a Windows ZIP asset', () {
    final release = AppUpdateRelease.fromJson(
      _releaseJson(
        assets: [
          _assetJson('Thing-windows.exe'),
          _assetJson('Thing-windows.zip'),
          _assetJson('Thing-macOS.zip'),
        ],
      ),
    );

    expect(release.assetFor('windows')?.name, 'Thing-windows.zip');
  });

  test('does not report an older or equal release', () async {
    final service = AppUpdateService(
      currentVersion: '0.1.5',
      operatingSystem: 'macos',
      fetchJson: (_) async => jsonEncode(_releaseJson()),
    );

    expect(await service.checkForUpdate(), isNull);
    expect(isNewerAppVersion('0.1.5', '0.1.5'), isFalse);
    expect(isNewerAppVersion('0.1.6', '0.1.5'), isTrue);
  });

  test('compares versions by numeric components', () {
    expect(isNewerAppVersion('v1.10.0', '1.9.9'), isTrue);
    expect(isNewerAppVersion('1.2.0', '1.2'), isFalse);
    expect(isNewerAppVersion('1.2.1', '1.2.0.9'), isTrue);
    expect(isNewerAppVersion('1.1.99', '1.2.0'), isFalse);
  });

  test('prefers a macOS DMG when both macOS package types exist', () {
    final release = AppUpdateRelease.fromJson(_releaseJson(macAssets: true));

    expect(release.assetFor('macos')?.name, 'Thing-macOS.dmg');
    expect(release.assetFor('android'), isNull);
  });

  test('parses release metadata and reports missing assets', () {
    final release = AppUpdateRelease.fromJson(
      _releaseJson(
        assets: [
          _assetJson('Thing-linux.zip'),
          {'name': 'invalid-download-url', 'browser_download_url': 'not a uri'},
          {'name': 'missing-url'},
          'invalid asset',
        ],
      ),
    );

    expect(release.version, '0.1.5');
    expect(release.tagName, 'v0.1.5');
    expect(release.notes, '修复更新功能。');
    expect(release.assets, hasLength(1));
    expect(release.assets.single.name, 'Thing-linux.zip');
    expect(release.assetFor('windows'), isNull);
    expect(release.assetFor('macos'), isNull);
  });
}

Map<String, dynamic> _releaseJson({
  bool macAssets = false,
  List<dynamic>? assets,
}) => {
  'tag_name': 'v0.1.5',
  'html_url': 'https://github.com/duochifan2003/Thing/releases/tag/v0.1.5',
  'body': '修复更新功能。',
  'assets':
      assets ??
      [
        _assetJson('Thing-windows.zip'),
        if (macAssets) _assetJson('Thing-macOS.zip'),
        if (macAssets) _assetJson('Thing-macOS.dmg'),
      ],
};

Map<String, String> _assetJson(String name) => {
  'name': name,
  'browser_download_url':
      'https://github.com/duochifan2003/Thing/releases/download/v0.1.5/$name',
};
