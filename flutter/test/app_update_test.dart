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
      expect(
        release?.assetFor('windows')?.name,
        'Thing-windows-v0.1.19-setup.exe',
      );
    },
  );

  test('selects Windows setup installer over the ZIP package', () {
    final release = AppUpdateRelease.fromJson(
      _releaseJson(
        assets: [
          _assetJson(
            'Thing-windows-v0.1.19-setup.exe',
            size: 13177394,
            digest:
                'sha256:961adf40eb6795d3cc487d402d16d6c6247d503620e93bd3726ad72f7bc1b2d7',
          ),
          _assetJson('Thing-windows-v0.1.19.zip', size: 15440124),
          _assetJson(
            'Thing-macOS-v0.1.19.dmg',
            size: 26523070,
            digest:
                'sha256:08587106257237b90fc0c6f92ac5b43aeb7eb29105ec3dd0a16c5f0d0e1809a8',
          ),
        ],
      ),
    );

    final asset = release.assetFor('windows');
    expect(asset?.name, 'Thing-windows-v0.1.19-setup.exe');
    expect(asset?.size, 13177394);
    expect(
      asset?.sha256,
      '961adf40eb6795d3cc487d402d16d6c6247d503620e93bd3726ad72f7bc1b2d7',
    );
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

    final asset = release.assetFor('macos');
    expect(asset?.name, 'Thing-macOS-v0.1.19.dmg');
    expect(asset?.size, 26523070);
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
        _assetJson(
          'Thing-windows-v0.1.19-setup.exe',
          size: 13177394,
          digest:
              'sha256:961adf40eb6795d3cc487d402d16d6c6247d503620e93bd3726ad72f7bc1b2d7',
        ),
        _assetJson(
          'Thing-windows-v0.1.19.zip',
          size: 15440124,
          digest:
              'sha256:5428b616a0cc4981be6dd0d203ce6f2389d5fc54e51d9958064aadbfe198a4f6',
        ),
        if (macAssets) _assetJson('Thing-macOS-v0.1.19.zip'),
        if (macAssets)
          _assetJson(
            'Thing-macOS-v0.1.19.dmg',
            size: 26523070,
            digest:
                'sha256:08587106257237b90fc0c6f92ac5b43aeb7eb29105ec3dd0a16c5f0d0e1809a8',
          ),
      ],
};

Map<String, dynamic> _assetJson(
  String name, {
  int size = 15440124,
  String digest =
      'sha256:5428b616a0cc4981be6dd0d203ce6f2389d5fc54e51d9958064aadbfe198a4f6',
}) => {
  'name': name,
  'browser_download_url':
      'https://github.com/duochifan2003/Thing/releases/download/v0.1.19/$name',
  'size': size,
  'digest': digest,
};
