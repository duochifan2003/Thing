import 'dart:convert';
import 'dart:io' as io;

import 'package:desktop_updater/desktop_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:person_event_atlas/app_update.dart';

class FakeDesktopUpdater extends DesktopUpdater {
  FakeDesktopUpdater({this.stageResult, this.downloadError, this.installError});

  final UpdateStageResult? stageResult;
  final Object? downloadError;
  final Object? installError;

  ReleaseDescriptor? lastDescriptor;
  String? lastStagedPath;
  bool? lastAllowUnsignedMacOSUpdates;

  @override
  Future<UpdateStageResult> downloadZipFirstUpdate({
    required Uri appArchiveUrl,
    required DesktopVersionInfo currentVersion,
    required ReleaseDescriptor descriptor,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    UpdateRequestHeadersProvider? requestHeadersProvider,
  }) async {
    lastDescriptor = descriptor;
    if (downloadError != null) throw downloadError!;
    onProgress?.call(100, 100);
    return stageResult ??
        UpdateStageResult(
          descriptor: descriptor,
          stagingPath: '/fake/staging/path',
        );
  }

  @override
  Future<void> installUpdate({
    required String stagingPath,
    List<String> removedFiles = const [],
    bool allowUnsignedMacOSUpdates = false,
    String? diagnosticsLogPath,
  }) async {
    lastStagedPath = stagingPath;
    lastAllowUnsignedMacOSUpdates = allowUnsignedMacOSUpdates;
    if (installError != null) throw installError!;
  }
}

void main() {
  group('checkForUpdate', () {
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

    test('prefers a macOS ZIP package when both macOS package types exist', () {
      final release = AppUpdateRelease.fromJson(_releaseJson(macAssets: true));

      final asset = release.assetFor('macos');
      expect(asset?.name, 'Thing-macOS-v0.1.19.zip');
      expect(asset?.size, 15440124);
      expect(release.assetFor('android'), isNull);
    });

    test('parses release metadata and reports missing assets', () {
      final release = AppUpdateRelease.fromJson(
        _releaseJson(
          assets: [
            _assetJson('Thing-linux.zip'),
            {
              'name': 'invalid-download-url',
              'browser_download_url': 'not a uri',
            },
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

    test('parses SHA-256 from asset sha256 property', () {
      final release = AppUpdateRelease.fromJson({
        'tag_name': 'v0.2.0',
        'html_url':
            'https://github.com/duochifan2003/Thing/releases/tag/v0.2.0',
        'body': 'New release notes',
        'assets': [
          {
            'name': 'Thing-macOS-v0.2.0.dmg',
            'browser_download_url':
                'https://github.com/duochifan2003/Thing/releases/download/v0.2.0/Thing-macOS-v0.2.0.dmg',
            'size': 123456,
            'sha256':
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          },
        ],
      });

      final asset = release.assetFor('macos');
      expect(asset?.name, 'Thing-macOS-v0.2.0.dmg');
      expect(
        asset?.sha256,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
    });

    test('parses SHA-256 from release body lines with various formats', () {
      final body = '''
## Checksums
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  Thing-windows-v0.2.0-setup.exe
Thing-macOS-v0.2.0.dmg: cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
SHA256(Thing-linux.zip) = dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
''';
      final release = AppUpdateRelease.fromJson({
        'tag_name': 'v0.2.0',
        'html_url':
            'https://github.com/duochifan2003/Thing/releases/tag/v0.2.0',
        'body': body,
        'assets': [
          {
            'name': 'Thing-windows-v0.2.0-setup.exe',
            'browser_download_url':
                'https://github.com/duochifan2003/Thing/releases/download/v0.2.0/Thing-windows-v0.2.0-setup.exe',
            'size': 200000,
          },
          {
            'name': 'Thing-macOS-v0.2.0.dmg',
            'browser_download_url':
                'https://github.com/duochifan2003/Thing/releases/download/v0.2.0/Thing-macOS-v0.2.0.dmg',
            'size': 300000,
          },
        ],
      });

      expect(
        release.assetFor('windows')?.sha256,
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      expect(
        release.assetFor('macos')?.sha256,
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      );
    });

    test('throws FormatException on malformed release json', () {
      expect(
        () => AppUpdateRelease.fromJson({'body': 'no tag'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AppUpdateRelease.fromJson({
          'tag_name': 'v1.0.0',
          'html_url': 'http://insecure-site.com',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws AppUpdateException when response is 404 not found', () async {
      final service = AppUpdateService(
        currentVersion: '0.1.0',
        fetchJson: (_) async => throw const AppUpdateException(
          '无法读取 GitHub 更新源。仓库可能是私有的，请公开仓库或配置访问令牌。',
        ),
      );

      expect(
        () => service.checkForUpdate(),
        throwsA(
          isA<AppUpdateException>().having(
            (e) => e.message,
            'message',
            contains('无法读取 GitHub 更新源'),
          ),
        ),
      );
    });

    test('throws AppUpdateException on network failure', () async {
      final service = AppUpdateService(
        currentVersion: '0.1.0',
        fetchJson: (_) async =>
            throw const AppUpdateException('无法连接 GitHub，请检查网络后重试。'),
      );

      expect(
        () => service.checkForUpdate(),
        throwsA(
          isA<AppUpdateException>().having(
            (e) => e.message,
            'message',
            contains('无法连接 GitHub'),
          ),
        ),
      );
    });

    test('throws AppUpdateException when no compatible asset exists', () async {
      final service = AppUpdateService(
        currentVersion: '0.1.0',
        operatingSystem: 'windows',
        fetchJson: (_) async => jsonEncode({
          'tag_name': 'v0.2.0',
          'html_url':
              'https://github.com/duochifan2003/Thing/releases/tag/v0.2.0',
          'body': 'Notes',
          'assets': [
            {
              'name': 'Thing-macOS-v0.2.0.dmg',
              'browser_download_url':
                  'https://github.com/duochifan2003/Thing/releases/download/v0.2.0/Thing-macOS-v0.2.0.dmg',
              'size': 12345,
            },
          ],
        }),
      );

      expect(
        () => service.checkForUpdate(),
        throwsA(
          isA<AppUpdateException>().having(
            (e) => e.message,
            'message',
            contains('没有适用于当前系统的安装包'),
          ),
        ),
      );
    });
  });

  group('downloadAndInstall', () {
    test('throws on unsupported operating systems (linux/android)', () async {
      final service = AppUpdateService(
        currentVersion: '0.1.0',
        operatingSystem: 'linux',
      );
      final release = AppUpdateRelease.fromJson(
        _releaseJson(assets: [_assetJson('Thing-linux.zip', size: 1000)]),
      );

      // On linux, assetFor('linux') is null
      expect(
        () => service.downloadAndInstall(release),
        throwsA(
          isA<AppUpdateException>().having(
            (e) => e.message,
            'message',
            contains('当前系统没有可用的更新包'),
          ),
        ),
      );
    });

    test('throws when asset size is invalid', () async {
      final service = AppUpdateService(
        currentVersion: '0.1.0',
        operatingSystem: 'macos',
      );
      final release = AppUpdateRelease.fromJson(
        _releaseJson(assets: [_assetJson('Thing-macOS-v0.1.19.dmg', size: 0)]),
      );

      expect(
        () => service.downloadAndInstall(release),
        throwsA(
          isA<AppUpdateException>().having(
            (e) => e.message,
            'message',
            contains('GitHub 更新包大小无效'),
          ),
        ),
      );
    });

    test('throws when asset sha256 is missing or malformed', () async {
      final service = AppUpdateService(
        currentVersion: '0.1.0',
        operatingSystem: 'macos',
      );
      final release = AppUpdateRelease.fromJson({
        'tag_name': 'v0.2.0',
        'html_url':
            'https://github.com/duochifan2003/Thing/releases/tag/v0.2.0',
        'body': 'Notes',
        'assets': [
          {
            'name': 'Thing-macOS-v0.2.0.dmg',
            'browser_download_url':
                'https://github.com/duochifan2003/Thing/releases/download/v0.2.0/Thing-macOS-v0.2.0.dmg',
            'size': 12345,
            'sha256': 'invalid_short_hash',
          },
        ],
      });

      expect(
        () => service.downloadAndInstall(release),
        throwsA(
          isA<AppUpdateException>().having(
            (e) => e.message,
            'message',
            contains('缺少有效的 SHA-256 校验信息'),
          ),
        ),
      );
    });

    test(
      'downloads and requests install on macOS with DMG package (allowUnsignedMacOSUpdates=true)',
      () async {
        final fakeUpdater = FakeDesktopUpdater();
        int? exitedWith;
        double? reportedProgress;
        final service = AppUpdateService(
          currentVersion: '0.1.0',
          operatingSystem: 'macos',
          exitApp: (code) {
            exitedWith = code;
            throw 'exited_$code';
          },
          desktopUpdater: fakeUpdater,
        );

        final release = AppUpdateRelease.fromJson(
          _releaseJson(
            assets: [
              _assetJson(
                'Thing-macOS-v0.1.19.dmg',
                size: 26523070,
                digest:
                    'sha256:08587106257237b90fc0c6f92ac5b43aeb7eb29105ec3dd0a16c5f0d0e1809a8',
              ),
            ],
          ),
        );

        expect(
          service.downloadAndInstall(
            release,
            onProgress: (p) => reportedProgress = p,
          ),
          throwsA('exited_0'),
        );

        await pumpEventQueue();

        expect(exitedWith, 0);
        expect(reportedProgress, 1.0);
        expect(fakeUpdater.lastDescriptor?.platform, 'macos');
        expect(fakeUpdater.lastDescriptor?.appName, 'Thing.app');
        expect(fakeUpdater.lastDescriptor?.artifact.kind, 'dmg');
        expect(
          fakeUpdater.lastDescriptor?.install.macosDmg?.appBundleName,
          'Thing.app',
        );
        expect(
          fakeUpdater.lastDescriptor?.install.macosDmg?.verifyPrimarySignature,
          isFalse,
        );
        expect(fakeUpdater.lastAllowUnsignedMacOSUpdates, isTrue);
        expect(fakeUpdater.lastStagedPath, '/fake/staging/path');
      },
    );

    test(
      'downloads and requests install on macOS with ZIP-only package (allowUnsignedMacOSUpdates=true, appName=Thing.app)',
      () async {
        final fakeUpdater = FakeDesktopUpdater();
        int? exitedWith;
        double? reportedProgress;
        final service = AppUpdateService(
          currentVersion: '0.1.0',
          operatingSystem: 'macos',
          exitApp: (code) {
            exitedWith = code;
            throw 'exited_$code';
          },
          desktopUpdater: fakeUpdater,
        );

        final release = AppUpdateRelease.fromJson(
          _releaseJson(
            assets: [
              _assetJson(
                'Thing-macOS-v0.1.19.zip',
                size: 25440124,
                digest:
                    'sha256:5428b616a0cc4981be6dd0d203ce6f2389d5fc54e51d9958064aadbfe198a4f6',
              ),
            ],
          ),
        );

        expect(
          service.downloadAndInstall(
            release,
            onProgress: (p) => reportedProgress = p,
          ),
          throwsA('exited_0'),
        );

        await pumpEventQueue();

        expect(exitedWith, 0);
        expect(reportedProgress, 1.0);
        expect(fakeUpdater.lastDescriptor?.platform, 'macos');
        expect(fakeUpdater.lastDescriptor?.appName, 'Thing.app');
        expect(fakeUpdater.lastDescriptor?.artifact.kind, 'zip');
        expect(
          fakeUpdater.lastDescriptor?.install.strategy,
          'wholeDirectoryReplace',
        );
        expect(fakeUpdater.lastAllowUnsignedMacOSUpdates, isTrue);
        expect(fakeUpdater.lastStagedPath, '/fake/staging/path');
      },
    );

    test(
      'downloads and requests install on Windows with authenticode.required=false',
      () async {
        final fakeUpdater = FakeDesktopUpdater();
        int? exitedWith;
        final service = AppUpdateService(
          currentVersion: '0.1.0',
          operatingSystem: 'windows',
          exitApp: (code) {
            exitedWith = code;
            throw 'exited_$code';
          },
          desktopUpdater: fakeUpdater,
        );

        final release = AppUpdateRelease.fromJson(
          _releaseJson(
            assets: [
              _assetJson(
                'Thing-windows-v0.1.19-setup.exe',
                size: 13177394,
                digest:
                    'sha256:961adf40eb6795d3cc487d402d16d6c6247d503620e93bd3726ad72f7bc1b2d7',
              ),
            ],
          ),
        );

        expect(service.downloadAndInstall(release), throwsA('exited_0'));

        await pumpEventQueue();

        expect(exitedWith, 0);
        expect(fakeUpdater.lastDescriptor?.platform, 'windows');
        expect(fakeUpdater.lastDescriptor?.artifact.kind, 'innoInstaller');
        expect(
          fakeUpdater.lastDescriptor?.install.inno?.authenticode.required,
          isFalse,
        );
      },
    );

    test('wraps desktopUpdater download error in AppUpdateException', () async {
      final fakeUpdater = FakeDesktopUpdater(
        downloadError: const io.FileSystemException('Download interrupted'),
      );
      final service = AppUpdateService(
        currentVersion: '0.1.0',
        operatingSystem: 'macos',
        desktopUpdater: fakeUpdater,
      );

      final release = AppUpdateRelease.fromJson(
        _releaseJson(
          assets: [
            _assetJson(
              'Thing-macOS-v0.1.19.dmg',
              size: 26523070,
              digest:
                  'sha256:08587106257237b90fc0c6f92ac5b43aeb7eb29105ec3dd0a16c5f0d0e1809a8',
            ),
          ],
        ),
      );

      expect(
        () => service.downloadAndInstall(release),
        throwsA(
          isA<AppUpdateException>().having(
            (e) => e.message,
            'message',
            contains('更新安装失败'),
          ),
        ),
      );
    });
  });

  group('version constants', () {
    test('fallback constants match expected release version', () {
      expect(appVersion, '0.1.22');
      expect(appBuild, '45');
      expect(appVersionLabel, 'v0.1.22+45');
    });
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
