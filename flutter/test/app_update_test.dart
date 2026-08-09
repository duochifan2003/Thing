import 'dart:convert';
import 'dart:io' as io;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:desktop_updater/desktop_updater.dart';
import 'package:desktop_updater/desktop_updater_platform_interface.dart';
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

  test('parses per-asset signature descriptions from release metadata', () {
    final release = AppUpdateRelease.fromJson({
      'tag_name': 'v0.1.5',
      'html_url': 'https://github.com/duochifan2003/Thing/releases/tag/v0.1.5',
      'body': '''
```json
{
  "signatures": {
    "Thing-windows-v0.1.5-setup.exe": {
      "algorithm": "ed25519",
      "publicKeyId": "thing-release-2026",
      "value": "signed-descriptor"
    }
  }
}
```
''',
      'assets': [_assetJson('Thing-windows-v0.1.5-setup.exe', size: 4)],
    });

    expect(
      release.assetFor('windows')?.signature?.publicKeyId,
      'thing-release-2026',
    );
  });

  test('parses release signatures from body with single signature object', () {
    final release = AppUpdateRelease.fromJson({
      'tag_name': 'v0.1.5',
      'html_url': 'https://github.com/duochifan2003/Thing/releases/tag/v0.1.5',
      'body': '''
```json
{
  "signature": {
    "algorithm": "ed25519",
    "publicKeyId": "thing-release-2026",
    "value": "top-level-signed"
  }
}
```
''',
      'assets': [_assetJson('Thing-windows-v0.1.5.zip', size: 4)],
    });

    expect(
      release.assetFor('windows')?.signature?.publicKeyId,
      'thing-release-2026',
    );
  });

  test(
    'downloads a signed installer, verifies it, then hands it to install',
    () async {
      final bytes = _zipBytes();
      final server = await _ArtifactServer.start(bytes);
      String? installedPath;
      try {
        final trustedKey = await _keyPair(_trustedSeed);
        final release = await _windowsRelease(
          downloadUrl: server.uri,
          expectedBytes: bytes,
          signingKey: trustedKey,
        );
        final service = await _service(
          trustedKey,
          installUpdate: (path) async => installedPath = path,
        );

        await expectLater(
          service.downloadAndInstall(release),
          throwsA(isA<_ExitException>()),
        );

        expect(server.requests, 1);
        expect(installedPath, isNotNull);
        expect(
          io.File('${installedPath!}/Thing.exe').readAsStringSync(),
          'test',
        );
        expect(
          io.File(
            '${installedPath!}/.desktop_updater_release_manifest.json',
          ).existsSync(),
          isTrue,
        );
      } finally {
        await server.close();
        if (installedPath != null) {
          await io.Directory(installedPath!).delete(recursive: true);
        }
      }
    },
  );

  test(
    'downloads and stages update, executing DesktopUpdater production installUpdate handoff',
    () async {
      final bytes = _zipBytes();
      final server = await _ArtifactServer.start(bytes);
      final fakePlatform = _FakeDesktopUpdaterPlatform();
      final originalPlatform = DesktopUpdaterPlatform.instance;
      DesktopUpdaterPlatform.instance = fakePlatform;
      try {
        final trustedKey = await _keyPair(_trustedSeed);
        final release = await _windowsRelease(
          downloadUrl: server.uri,
          expectedBytes: bytes,
          signingKey: trustedKey,
        );
        final service = await _service(trustedKey);

        await expectLater(
          service.downloadAndInstall(release),
          throwsA(isA<_ExitException>()),
        );

        expect(server.requests, 1);
        expect(fakePlatform.installCalls, 1);
        expect(fakePlatform.allowUnsignedMacOSUpdates, isFalse);
        expect(fakePlatform.installedStagingPath, isNotNull);
        final stagedPath = fakePlatform.installedStagingPath!;
        expect(io.File('$stagedPath/Thing.exe').readAsStringSync(), 'test');
        final manifestFile = io.File(
          '$stagedPath/.desktop_updater_release_manifest.json',
        );
        expect(manifestFile.existsSync(), isTrue);
        final manifestJson = jsonDecode(manifestFile.readAsStringSync());
        expect(manifestJson['appName'], 'Thing');
        expect(manifestJson['version'], '0.1.28');
        expect(manifestJson['install']['strategy'], 'wholeDirectoryReplace');
      } finally {
        DesktopUpdaterPlatform.instance = originalPlatform;
        await server.close();
        if (fakePlatform.installedStagingPath != null) {
          await io.Directory(
            fakePlatform.installedStagingPath!,
          ).delete(recursive: true);
        }
      }
    },
  );

  test(
    'stages Inno installer with Authenticode requirement and pinned thumbprints',
    () async {
      final bytes = <int>[1, 2, 3, 4, 5];
      final server = await _ArtifactServer.start(bytes);
      final fakePlatform = _FakeDesktopUpdaterPlatform();
      final originalPlatform = DesktopUpdaterPlatform.instance;
      DesktopUpdaterPlatform.instance = fakePlatform;
      try {
        final trustedKey = await _keyPair(_trustedSeed);
        final release = await _innoRelease(
          downloadUrl: server.uri,
          expectedBytes: bytes,
          signingKey: trustedKey,
        );
        final service = await _service(
          trustedKey,
          pinnedAuthenticodeThumbprints: [_testThumbprint],
        );

        if (io.Platform.isWindows) {
          await expectLater(
            service.downloadAndInstall(release),
            throwsA(isA<_ExitException>()),
          );

          expect(server.requests, 1);
          expect(fakePlatform.installCalls, 1);
          expect(fakePlatform.allowUnsignedMacOSUpdates, isFalse);
          final stagedPath = fakePlatform.installedStagingPath!;
          expect(io.File('$stagedPath/installer.exe').existsSync(), isTrue);
          final manifestFile = io.File(
            '$stagedPath/.desktop_updater_release_manifest.json',
          );
          expect(manifestFile.existsSync(), isTrue);
          final manifestJson = jsonDecode(manifestFile.readAsStringSync());
          expect(manifestJson['install']['strategy'], 'innoInstaller');
          expect(
            manifestJson['install']['inno']['authenticode']['required'],
            isTrue,
          );
          expect(
            manifestJson['install']['inno']['authenticode']['sha256Thumbprints'],
            [_testThumbprint],
          );
        } else {
          await expectLater(
            service.downloadAndInstall(release),
            throwsA(
              isA<AppUpdateException>().having(
                (error) => error.message,
                'message',
                contains(
                  'Inno installer updates are only supported on Windows',
                ),
              ),
            ),
          );
        }
      } finally {
        DesktopUpdaterPlatform.instance = originalPlatform;
        await server.close();
        if (fakePlatform.installedStagingPath != null) {
          await io.Directory(
            fakePlatform.installedStagingPath!,
          ).delete(recursive: true);
        }
      }
    },
  );

  test(
    'rejects Inno installer update when Authenticode thumbprint is not configured',
    () async {
      final bytes = <int>[1, 2, 3, 4, 5];
      final server = await _ArtifactServer.start(bytes);
      final fakePlatform = _FakeDesktopUpdaterPlatform();
      final originalPlatform = DesktopUpdaterPlatform.instance;
      DesktopUpdaterPlatform.instance = fakePlatform;
      try {
        final trustedKey = await _keyPair(_trustedSeed);
        final release = await _innoRelease(
          downloadUrl: server.uri,
          expectedBytes: bytes,
          signingKey: trustedKey,
        );
        final service = await _service(
          trustedKey,
          pinnedAuthenticodeThumbprints: const [],
        );

        await expectLater(
          service.downloadAndInstall(release),
          throwsA(
            isA<AppUpdateException>().having(
              (error) => error.message,
              'message',
              contains('WINDOWS_AUTHENTICODE_SHA256'),
            ),
          ),
        );

        expect(server.requests, 0);
        expect(fakePlatform.installCalls, 0);
      } finally {
        DesktopUpdaterPlatform.instance = originalPlatform;
        await server.close();
      }
    },
  );

  test(
    'rejects Inno installer update when Authenticode thumbprint is invalid hex format',
    () async {
      final bytes = <int>[1, 2, 3, 4, 5];
      final server = await _ArtifactServer.start(bytes);
      final fakePlatform = _FakeDesktopUpdaterPlatform();
      final originalPlatform = DesktopUpdaterPlatform.instance;
      DesktopUpdaterPlatform.instance = fakePlatform;
      try {
        final trustedKey = await _keyPair(_trustedSeed);
        final release = await _innoRelease(
          downloadUrl: server.uri,
          expectedBytes: bytes,
          signingKey: trustedKey,
        );
        final service = await _service(
          trustedKey,
          pinnedAuthenticodeThumbprints: const ['invalid-not-64-hex'],
        );

        await expectLater(
          service.downloadAndInstall(release),
          throwsA(
            isA<AppUpdateException>().having(
              (error) => error.message,
              'message',
              contains('格式无效'),
            ),
          ),
        );

        expect(server.requests, 0);
        expect(fakePlatform.installCalls, 0);
      } finally {
        DesktopUpdaterPlatform.instance = originalPlatform;
        await server.close();
      }
    },
  );

  test('parses and normalizes Authenticode thumbprints correctly', () {
    expect(parseAuthenticodeThumbprints(''), isEmpty);
    expect(parseAuthenticodeThumbprints('   '), isEmpty);
    expect(parseAuthenticodeThumbprints('AA:BB:CC:DD${':00' * 28}'), [
      'aabbccdd${'00' * 28}',
    ]);
    expect(
      parseAuthenticodeThumbprints(
        '  ${'11' * 32} , \n ${'22:33' * 16} ; ${'44' * 32}  ',
      ),
      ['11' * 32, '2233' * 16, '44' * 32],
    );
  });

  test('rejects a tampered artifact before installer handoff', () async {
    final expectedBytes = _zipBytes();
    final tamperedBytes = <int>[
      ...expectedBytes.sublist(0, expectedBytes.length - 1),
      expectedBytes.last ^ 1,
    ];
    final server = await _ArtifactServer.start(tamperedBytes);
    final trustedKey = await _keyPair(_trustedSeed);
    try {
      final release = await _windowsRelease(
        downloadUrl: server.uri,
        expectedBytes: expectedBytes,
        signingKey: trustedKey,
      );
      var installed = false;
      final service = await _service(
        trustedKey,
        installUpdate: (_) async => installed = true,
      );

      await expectLater(
        service.downloadAndInstall(release),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.message,
            'message',
            contains('完整性校验失败'),
          ),
        ),
      );
      expect(server.requests, 1);
      expect(installed, isFalse);
    } finally {
      await server.close();
    }
  });

  test(
    'rejects an update with no descriptor signature before download',
    () async {
      final server = await _ArtifactServer.start(_zipBytes());
      final trustedKey = await _keyPair(_trustedSeed);
      try {
        final release = await _windowsRelease(
          downloadUrl: server.uri,
          expectedBytes: _zipBytes(),
          signingKey: null,
        );
        final service = await _service(trustedKey);

        await expectLater(
          service.downloadAndInstall(release),
          throwsA(
            isA<AppUpdateException>().having(
              (error) => error.message,
              'message',
              contains('签名'),
            ),
          ),
        );
        expect(server.requests, 0);
      } finally {
        await server.close();
      }
    },
  );

  test('rejects an update with a forged descriptor signature', () async {
    final server = await _ArtifactServer.start(_zipBytes());
    final trustedKey = await _keyPair(_trustedSeed);
    final wrongKey = await _keyPair(_wrongSeed);
    try {
      final release = await _windowsRelease(
        downloadUrl: server.uri,
        expectedBytes: _zipBytes(),
        signingKey: wrongKey,
      );
      final service = await _service(trustedKey);

      await expectLater(
        service.downloadAndInstall(release),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.message,
            'message',
            contains('签名'),
          ),
        ),
      );
      expect(server.requests, 0);
    } finally {
      await server.close();
    }
  });

  test('rejects update when public key ID is not pinned/trusted', () async {
    final server = await _ArtifactServer.start(_zipBytes());
    final trustedKey = await _keyPair(_trustedSeed);
    try {
      final placeholder = const ReleaseSignature(
        algorithm: 'ed25519',
        publicKeyId: 'untrusted-key-id',
        value: '',
      );
      final unsignedDescriptor = _windowsDescriptor(
        downloadUrl: server.uri,
        expectedBytes: _zipBytes(),
        signature: placeholder,
      );
      final signature = ReleaseSignature(
        algorithm: 'ed25519',
        publicKeyId: 'untrusted-key-id',
        value: base64Encode(
          (await Ed25519().sign(
            unsignedDescriptor.canonicalSignatureBytes(),
            keyPair: trustedKey,
          )).bytes,
        ),
      );
      final release = AppUpdateRelease(
        version: '0.1.28',
        tagName: 'v0.1.28',
        htmlUrl: Uri.parse(
          'https://github.com/duochifan2003/Thing/releases/tag/v0.1.28',
        ),
        notes: 'untrusted key release',
        generatedAt: _testTimestamp,
        assets: [
          AppUpdateAsset(
            name: 'Thing-windows-v0.1.28.zip',
            downloadUrl: server.uri,
            size: _zipBytes().length,
            sha256: crypto.sha256.convert(_zipBytes()).toString(),
            signature: signature,
          ),
        ],
      );

      final service = await _service(trustedKey);

      await expectLater(
        service.downloadAndInstall(release),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.message,
            'message',
            contains('签名'),
          ),
        ),
      );
      expect(server.requests, 0);
    } finally {
      await server.close();
    }
  });
}

class _FakeDesktopUpdaterPlatform extends DesktopUpdaterPlatform {
  String? installedStagingPath;
  bool? allowUnsignedMacOSUpdates;
  List<String> removedFiles = const [];
  String? diagnosticsLogPath;
  int installCalls = 0;

  @override
  Future<void> installUpdate({
    required String stagingPath,
    List<String> removedFiles = const [],
    bool allowUnsignedMacOSUpdates = false,
    String? diagnosticsLogPath,
  }) async {
    installCalls++;
    installedStagingPath = stagingPath;
    this.removedFiles = removedFiles;
    this.allowUnsignedMacOSUpdates = allowUnsignedMacOSUpdates;
    this.diagnosticsLogPath = diagnosticsLogPath;
  }
}

const _testKeyId = 'test-release-key';
const _trustedSeed = <int>[
  0,
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
  26,
  27,
  28,
  29,
  30,
  31,
];
const _wrongSeed = <int>[
  31,
  30,
  29,
  28,
  27,
  26,
  25,
  24,
  23,
  22,
  21,
  20,
  19,
  18,
  17,
  16,
  15,
  14,
  13,
  12,
  11,
  10,
  9,
  8,
  7,
  6,
  5,
  4,
  3,
  2,
  1,
  0,
];
final _testThumbprint = List.filled(64, 'a').join();
final _testTimestamp = DateTime.utc(2026, 8, 9);

Future<SimpleKeyPair> _keyPair(List<int> seed) {
  return Ed25519().newKeyPairFromSeed(seed);
}

Future<Map<String, String>> _publicKeys(SimpleKeyPair keyPair) async {
  final publicKey = await keyPair.extractPublicKey();
  return {_testKeyId: base64Encode(publicKey.bytes)};
}

Future<AppUpdateService> _service(
  SimpleKeyPair trustedKey, {
  UpdateInstaller? installUpdate,
  List<String>? pinnedAuthenticodeThumbprints,
  String operatingSystem = 'windows',
}) async {
  return AppUpdateService(
    currentVersion: '0.1.22',
    operatingSystem: operatingSystem,
    exitApp: (_) => throw const _ExitException(),
    installUpdate: installUpdate,
    pinnedPublicKeys: await _publicKeys(trustedKey),
    pinnedAuthenticodeThumbprints:
        pinnedAuthenticodeThumbprints ?? [_testThumbprint],
  );
}

List<int> _zipBytes() {
  final archive = Archive()..addFile(ArchiveFile.string('Thing.exe', 'test'));
  return ZipEncoder().encode(archive);
}

Future<AppUpdateRelease> _windowsRelease({
  required Uri downloadUrl,
  required List<int> expectedBytes,
  required SimpleKeyPair? signingKey,
}) async {
  final placeholder = signingKey == null
      ? null
      : const ReleaseSignature(
          algorithm: 'ed25519',
          publicKeyId: _testKeyId,
          value: '',
        );
  final unsignedDescriptor = _windowsDescriptor(
    downloadUrl: downloadUrl,
    expectedBytes: expectedBytes,
    signature: placeholder,
  );
  final signature = signingKey == null
      ? null
      : ReleaseSignature(
          algorithm: 'ed25519',
          publicKeyId: _testKeyId,
          value: base64Encode(
            (await Ed25519().sign(
              unsignedDescriptor.canonicalSignatureBytes(),
              keyPair: signingKey,
            )).bytes,
          ),
        );
  return AppUpdateRelease(
    version: '0.1.28',
    tagName: 'v0.1.28',
    htmlUrl: Uri.parse(
      'https://github.com/duochifan2003/Thing/releases/tag/v0.1.28',
    ),
    notes: 'test release',
    generatedAt: _testTimestamp,
    assets: [
      AppUpdateAsset(
        name: 'Thing-windows-v0.1.28.zip',
        downloadUrl: downloadUrl,
        size: expectedBytes.length,
        sha256: crypto.sha256.convert(expectedBytes).toString(),
        signature: signature,
      ),
    ],
  );
}

ReleaseDescriptor _windowsDescriptor({
  required Uri downloadUrl,
  required List<int> expectedBytes,
  required ReleaseSignature? signature,
}) {
  return ReleaseDescriptor(
    schemaVersion: 3,
    packageId: 'local.munch.eventatlas',
    appName: 'Thing',
    version: '0.1.28',
    buildNumber: null,
    platform: 'windows',
    channel: 'stable',
    artifact: ReleaseArtifact(
      kind: 'zip',
      url: downloadUrl,
      sha256: crypto.sha256.convert(expectedBytes).toString(),
      length: expectedBytes.length,
    ),
    install: const ReleaseInstall(strategy: 'wholeDirectoryReplace'),
    signature: signature,
    minimumUpdaterVersion: '2.7.0',
    generatedAt: _testTimestamp,
  );
}

Future<AppUpdateRelease> _innoRelease({
  required Uri downloadUrl,
  required List<int> expectedBytes,
  required SimpleKeyPair? signingKey,
}) async {
  final placeholder = signingKey == null
      ? null
      : const ReleaseSignature(
          algorithm: 'ed25519',
          publicKeyId: _testKeyId,
          value: '',
        );
  final unsignedDescriptor = _innoDescriptor(
    downloadUrl: downloadUrl,
    expectedBytes: expectedBytes,
    signature: placeholder,
  );
  final signature = signingKey == null
      ? null
      : ReleaseSignature(
          algorithm: 'ed25519',
          publicKeyId: _testKeyId,
          value: base64Encode(
            (await Ed25519().sign(
              unsignedDescriptor.canonicalSignatureBytes(),
              keyPair: signingKey,
            )).bytes,
          ),
        );
  return AppUpdateRelease(
    version: '0.1.28',
    tagName: 'v0.1.28',
    htmlUrl: Uri.parse(
      'https://github.com/duochifan2003/Thing/releases/tag/v0.1.28',
    ),
    notes: 'test release',
    generatedAt: _testTimestamp,
    assets: [
      AppUpdateAsset(
        name: 'Thing-windows-v0.1.28-setup.exe',
        downloadUrl: downloadUrl,
        size: expectedBytes.length,
        sha256: crypto.sha256.convert(expectedBytes).toString(),
        signature: signature,
      ),
    ],
  );
}

ReleaseDescriptor _innoDescriptor({
  required Uri downloadUrl,
  required List<int> expectedBytes,
  required ReleaseSignature? signature,
}) {
  return ReleaseDescriptor(
    schemaVersion: 3,
    packageId: 'local.munch.eventatlas',
    appName: 'Thing',
    version: '0.1.28',
    buildNumber: null,
    platform: 'windows',
    channel: 'stable',
    artifact: ReleaseArtifact(
      kind: 'innoInstaller',
      url: downloadUrl,
      sha256: crypto.sha256.convert(expectedBytes).toString(),
      length: expectedBytes.length,
    ),
    install: ReleaseInstall(
      strategy: 'innoInstaller',
      inno: ReleaseInnoInstall(
        silentArgs: const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
        inheritInstallDirectory: true,
        logFileName: 'thing-update.log',
        relaunchAfterInstall: true,
        requiresElevation: 'auto',
        authenticode: ReleaseAuthenticodePolicy(
          required: true,
          sha256Thumbprints: [_testThumbprint],
        ),
      ),
    ),
    signature: signature,
    minimumUpdaterVersion: '2.7.0',
    generatedAt: _testTimestamp,
  );
}

class _ArtifactServer {
  _ArtifactServer(this._server, this._bytes);

  final io.HttpServer _server;
  final List<int> _bytes;
  int requests = 0;

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}/artifact.exe');

  static Future<_ArtifactServer> start(List<int> bytes) async {
    final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    final fixture = _ArtifactServer(server, List.unmodifiable(bytes));
    server.listen((request) async {
      fixture.requests++;
      request.response.headers.contentLength = fixture._bytes.length;
      request.response.add(fixture._bytes);
      await request.response.close();
    });
    return fixture;
  }

  Future<void> close() => _server.close(force: true);
}

class _ExitException implements Exception {
  const _ExitException();
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
