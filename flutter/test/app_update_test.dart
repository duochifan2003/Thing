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

  test('prefers a macOS DMG when both macOS package types exist', () {
    final release = AppUpdateRelease.fromJson(_releaseJson(macAssets: true));

    expect(release.assetFor('macos')?.name, 'Thing-macOS.dmg');
    expect(release.assetFor('android'), isNull);
  });
}

Map<String, dynamic> _releaseJson({bool macAssets = false}) => {
  'tag_name': 'v0.1.5',
  'html_url': 'https://github.com/duochifan2003/Thing/releases/tag/v0.1.5',
  'body': '修复更新功能。',
  'assets': [
    {
      'name': 'Thing-windows.zip',
      'browser_download_url':
          'https://github.com/duochifan2003/Thing/releases/download/v0.1.5/Thing-windows.zip',
    },
    if (macAssets)
      {
        'name': 'Thing-macOS.zip',
        'browser_download_url':
            'https://github.com/duochifan2003/Thing/releases/download/v0.1.5/Thing-macOS.zip',
      },
    if (macAssets)
      {
        'name': 'Thing-macOS.dmg',
        'browser_download_url':
            'https://github.com/duochifan2003/Thing/releases/download/v0.1.5/Thing-macOS.dmg',
      },
  ],
};
