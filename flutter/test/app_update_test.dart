import 'dart:convert';
import 'dart:io' as io;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:desktop_updater/desktop_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:person_event_atlas/app_update.dart';

void main() {
  test('parses latest release metadata and extracts update assets', () {
    final release = AppUpdateRelease.fromJson(_releaseJson(macAssets: true));

    expect(release.version, '0.1.5');
    expect(release.tagName, 'v0.1.5');
    expect(
      release.htmlUrl,
      Uri.parse('https://github.com/duochifan2003/Thing/releases/tag/v0.1.5'),
    );
    expect(release.notes, '修复更新功能。');
    expect(release.assets, hasLength(3));

    final windowsAsset = release.assetFor('windows');
    expect(windowsAsset, isNotNull);
    expect(windowsAsset!.name, 'Thing-windows-v0.1.19-setup.exe');
    expect(
      windowsAsset.descriptorUrl,
      Uri.parse(
        'https://github.com/duochifan2003/Thing/releases/download/v0.1.19/Thing-windows-v0.1.19-setup.exe.release.json',
      ),
    );

    final macAsset = release.assetFor('macos');
    expect(macAsset, isNotNull);
    expect(macAsset!.name, 'Thing-macOS-v0.1.19.dmg');
    expect(
      macAsset.descriptorUrl,
      Uri.parse(
        'https://github.com/duochifan2003/Thing/releases/download/v0.1.19/Thing-macOS-v0.1.19.dmg.release.json',
      ),
    );
  });

  test('compares semantic versions correctly', () {
    expect(isNewerAppVersion('0.1.28', '0.1.22'), isTrue);
    expect(isNewerAppVersion('v0.1.28', '0.1.28'), isFalse);
    expect(isNewerAppVersion('0.1.21', '0.1.22'), isFalse);
    expect(isNewerAppVersion('1.0.0', '0.9.9'), isTrue);
    expect(isNewerAppVersion('0.1.22.1', '0.1.22'), isTrue);
  });

  test('returns null when current version is up to date', () async {
    final trustedKey = await _keyPair(_trustedSeed);
    final service = AppUpdateService(
      currentVersion: '0.1.5',
      operatingSystem: 'windows',
      fetchJson: (_) async => jsonEncode(_releaseJson()),
      pinnedPublicKeys: await _publicKeys(trustedKey),
    );

    final release = await service.checkForUpdate();
    expect(release, isNull);
  });

  test('throws when release has no assets for the current platform', () async {
    final trustedKey = await _keyPair(_trustedSeed);
    final service = AppUpdateService(
      currentVersion: '0.1.0',
      operatingSystem: 'linux',
      fetchJson: (_) async => jsonEncode(_releaseJson()),
      pinnedPublicKeys: await _publicKeys(trustedKey),
    );

    await expectLater(
      service.checkForUpdate(),
      throwsA(
        isA<AppUpdateException>().having(
          (error) => error.message,
          'message',
          contains('没有适用于当前系统'),
        ),
      ),
    );
  });

  test(
    'stages Windows zip update via DesktopUpdater and verifies extracted files',
    () async {
      final zipBytes = _zipBytes();
      final trustedKey = await _keyPair(_trustedSeed);
      final server = await _MockReleaseServer.start(
        artifactBytes: zipBytes,
        artifactName: 'Thing-windows-v0.1.28.zip',
        signingKey: trustedKey,
        kind: 'zip',
      );
      String? installedPath;
      try {
        final service = await _service(
          trustedKey,
          installUpdate: (path) async => installedPath = path,
          fetchJson: server.fetchJson,
        );
        final release = await server.buildRelease();

        await expectLater(
          service.downloadAndInstall(release),
          throwsA(isA<_ExitException>()),
        );

        expect(server.artifactRequests, 1);
        expect(server.descriptorRequests, 1);
        expect(installedPath, isNotNull);
        expect(
          io.File('${installedPath!}/Thing.exe').readAsStringSync(),
          'test',
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
    'stages Inno installer with Authenticode requirement and pinned thumbprints',
    () async {
      final installerBytes = utf8.encode('mock-inno-installer-binary');
      final trustedKey = await _keyPair(_trustedSeed);
      final server = await _MockReleaseServer.start(
        artifactBytes: installerBytes,
        artifactName: 'Thing-windows-v0.1.28-setup.exe',
        signingKey: trustedKey,
        kind: 'innoInstaller',
      );
      String? stagedPath;
      ReleaseDescriptor? stagedDescriptor;
      try {
        final service = await _service(
          trustedKey,
          stageUpdate:
              ({
                required appArchiveUrl,
                required currentVersion,
                required descriptor,
                onProgress,
              }) async {
                stagedDescriptor = descriptor;
                return UpdateStageResult(
                  descriptor: descriptor,
                  stagingPath: '/mock/staging/inno',
                );
              },
          installUpdate: (path) async => stagedPath = path,
          fetchJson: server.fetchJson,
        );
        final release = await server.buildRelease();

        await expectLater(
          service.downloadAndInstall(release),
          throwsA(isA<_ExitException>()),
        );

        expect(server.descriptorRequests, 1);
        expect(stagedPath, '/mock/staging/inno');
        expect(stagedDescriptor, isNotNull);
        expect(stagedDescriptor!.install.strategy, 'innoInstaller');
        expect(stagedDescriptor!.install.inno!.authenticode.required, isTrue);
        expect(
          stagedDescriptor!.install.inno!.authenticode.sha256Thumbprints,
          contains(_testThumbprint),
        );
      } finally {
        await server.close();
      }
    },
  );

  test(
    'stages macOS DMG update with wholeBundleReplace and verifyPrimarySignature',
    () async {
      final dmgBytes = utf8.encode('mock-dmg-binary');
      final trustedKey = await _keyPair(_trustedSeed);
      final server = await _MockReleaseServer.start(
        artifactBytes: dmgBytes,
        artifactName: 'Thing-macOS-v0.1.28.dmg',
        signingKey: trustedKey,
        kind: 'dmg',
      );
      String? stagedPath;
      ReleaseDescriptor? stagedDescriptor;
      try {
        final service = await _service(
          trustedKey,
          operatingSystem: 'macos',
          stageUpdate:
              ({
                required appArchiveUrl,
                required currentVersion,
                required descriptor,
                onProgress,
              }) async {
                stagedDescriptor = descriptor;
                return UpdateStageResult(
                  descriptor: descriptor,
                  stagingPath: '/mock/staging/dmg',
                );
              },
          installUpdate: (path) async => stagedPath = path,
          fetchJson: server.fetchJson,
        );
        final release = await server.buildRelease();

        await expectLater(
          service.downloadAndInstall(release),
          throwsA(isA<_ExitException>()),
        );

        expect(server.descriptorRequests, 1);
        expect(stagedPath, '/mock/staging/dmg');
        expect(stagedDescriptor, isNotNull);
        expect(stagedDescriptor!.install.strategy, 'wholeBundleReplace');
        expect(
          stagedDescriptor!.install.macosDmg!.verifyPrimarySignature,
          isTrue,
        );
      } finally {
        await server.close();
      }
    },
  );

  test('rejects a tampered artifact before installer handoff', () async {
    final expectedBytes = _zipBytes();
    final tamperedBytes = <int>[
      ...expectedBytes.sublist(0, expectedBytes.length - 1),
      expectedBytes.last ^ 1,
    ];
    final trustedKey = await _keyPair(_trustedSeed);
    final server = await _MockReleaseServer.start(
      artifactBytes: tamperedBytes,
      expectedSha256Bytes: expectedBytes,
      artifactName: 'Thing-windows-v0.1.28.zip',
      signingKey: trustedKey,
      kind: 'zip',
    );
    try {
      var installed = false;
      final service = await _service(
        trustedKey,
        installUpdate: (_) async => installed = true,
        fetchJson: server.fetchJson,
      );
      final release = await server.buildRelease();

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
      expect(server.artifactRequests, 1);
      expect(server.descriptorRequests, 1);
      expect(installed, isFalse);
    } finally {
      await server.close();
    }
  });

  test(
    'rejects an update with missing descriptor asset (.release.json) before download',
    () async {
      final zipBytes = _zipBytes();
      final trustedKey = await _keyPair(_trustedSeed);
      final server = await _MockReleaseServer.start(
        artifactBytes: zipBytes,
        artifactName: 'Thing-windows-v0.1.28.zip',
        signingKey: trustedKey,
        kind: 'zip',
        includeDescriptorAsset: false,
      );
      try {
        final service = await _service(trustedKey, fetchJson: server.fetchJson);
        final release = await server.buildRelease();

        await expectLater(
          service.downloadAndInstall(release),
          throwsA(
            isA<AppUpdateException>().having(
              (error) => error.message,
              'message',
              contains('缺少对应的签名描述文件'),
            ),
          ),
        );
        expect(server.artifactRequests, 0);
      } finally {
        await server.close();
      }
    },
  );

  test(
    'rejects an update with no descriptor signature before download',
    () async {
      final zipBytes = _zipBytes();
      final trustedKey = await _keyPair(_trustedSeed);
      final server = await _MockReleaseServer.start(
        artifactBytes: zipBytes,
        artifactName: 'Thing-windows-v0.1.28.zip',
        signingKey: null,
        kind: 'zip',
      );
      try {
        final service = await _service(trustedKey, fetchJson: server.fetchJson);
        final release = await server.buildRelease();

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
        expect(server.artifactRequests, 0);
      } finally {
        await server.close();
      }
    },
  );

  test('rejects an update with a forged descriptor signature', () async {
    final zipBytes = _zipBytes();
    final trustedKey = await _keyPair(_trustedSeed);
    final wrongKey = await _keyPair(_wrongSeed);
    final server = await _MockReleaseServer.start(
      artifactBytes: zipBytes,
      artifactName: 'Thing-windows-v0.1.28.zip',
      signingKey: wrongKey,
      kind: 'zip',
    );
    try {
      final service = await _service(trustedKey, fetchJson: server.fetchJson);
      final release = await server.buildRelease();

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
      expect(server.artifactRequests, 0);
    } finally {
      await server.close();
    }
  });

  test(
    'rejects an update with descriptor / asset size mismatch before download',
    () async {
      final zipBytes = _zipBytes();
      final trustedKey = await _keyPair(_trustedSeed);
      final server = await _MockReleaseServer.start(
        artifactBytes: zipBytes,
        artifactName: 'Thing-windows-v0.1.28.zip',
        signingKey: trustedKey,
        kind: 'zip',
        overrideDescriptorLength: zipBytes.length + 100,
      );
      try {
        final service = await _service(trustedKey, fetchJson: server.fetchJson);
        final release = await server.buildRelease();

        await expectLater(
          service.downloadAndInstall(release),
          throwsA(
            isA<AppUpdateException>().having(
              (error) => error.message,
              'message',
              contains('文件大小与 Release 资产大小不一致'),
            ),
          ),
        );
        expect(server.artifactRequests, 0);
      } finally {
        await server.close();
      }
    },
  );

  test(
    'rejects Windows innoInstaller update when Authenticode pin is missing',
    () async {
      final installerBytes = utf8.encode('mock-inno-installer');
      final trustedKey = await _keyPair(_trustedSeed);
      final server = await _MockReleaseServer.start(
        artifactBytes: installerBytes,
        artifactName: 'Thing-windows-v0.1.28-setup.exe',
        signingKey: trustedKey,
        kind: 'innoInstaller',
      );
      try {
        final service = await _service(
          trustedKey,
          pinnedAuthenticodeThumbprints: const [],
          fetchJson: server.fetchJson,
        );
        final release = await server.buildRelease();

        await expectLater(
          service.downloadAndInstall(release),
          throwsA(
            isA<AppUpdateException>().having(
              (error) => error.message,
              'message',
              contains('未配置 Windows Authenticode 证书指纹'),
            ),
          ),
        );
        expect(server.artifactRequests, 0);
      } finally {
        await server.close();
      }
    },
  );

  test(
    'rejects Windows innoInstaller update when Authenticode thumbprint does not match',
    () async {
      final installerBytes = utf8.encode('mock-inno-installer');
      final trustedKey = await _keyPair(_trustedSeed);
      final server = await _MockReleaseServer.start(
        artifactBytes: installerBytes,
        artifactName: 'Thing-windows-v0.1.28-setup.exe',
        signingKey: trustedKey,
        kind: 'innoInstaller',
      );
      try {
        final mismatchedThumbprint = List.filled(64, 'b').join();
        final service = await _service(
          trustedKey,
          pinnedAuthenticodeThumbprints: [mismatchedThumbprint],
          fetchJson: server.fetchJson,
        );
        final release = await server.buildRelease();

        await expectLater(
          service.downloadAndInstall(release),
          throwsA(
            isA<AppUpdateException>().having(
              (error) => error.message,
              'message',
              contains('Authenticode 指纹与客户端固定指纹不匹配'),
            ),
          ),
        );
        expect(server.artifactRequests, 0);
      } finally {
        await server.close();
      }
    },
  );
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
  UpdateStager? stageUpdate,
  List<String>? pinnedAuthenticodeThumbprints,
  String operatingSystem = 'windows',
  UpdateJsonFetcher? fetchJson,
}) async {
  return AppUpdateService(
    currentVersion: '0.1.22',
    operatingSystem: operatingSystem,
    exitApp: (_) => throw const _ExitException(),
    installUpdate: installUpdate,
    stageUpdate: stageUpdate,
    fetchJson: fetchJson,
    pinnedPublicKeys: await _publicKeys(trustedKey),
    pinnedAuthenticodeThumbprints:
        pinnedAuthenticodeThumbprints ?? [_testThumbprint],
  );
}

List<int> _zipBytes() {
  final archive = Archive()..addFile(ArchiveFile.string('Thing.exe', 'test'));
  return ZipEncoder().encode(archive);
}

class _MockReleaseServer {
  _MockReleaseServer({
    required this.server,
    required this.artifactBytes,
    required this.artifactName,
    required this.descriptorJson,
    required this.includeDescriptorAsset,
  });

  final io.HttpServer server;
  final List<int> artifactBytes;
  final String artifactName;
  final String descriptorJson;
  final bool includeDescriptorAsset;

  int artifactRequests = 0;
  int descriptorRequests = 0;

  Uri get artifactUri =>
      Uri.parse('http://127.0.0.1:${server.port}/$artifactName');
  Uri get descriptorUri =>
      Uri.parse('http://127.0.0.1:${server.port}/$artifactName.release.json');

  Future<String> fetchJson(Uri uri) async {
    if (uri.toString().endsWith('.release.json')) {
      descriptorRequests++;
      return descriptorJson;
    }
    return '';
  }

  static Future<_MockReleaseServer> start({
    required List<int> artifactBytes,
    required String artifactName,
    required SimpleKeyPair? signingKey,
    required String kind,
    List<int>? expectedSha256Bytes,
    bool includeDescriptorAsset = true,
    int? overrideDescriptorLength,
  }) async {
    final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final artifactUri = Uri.parse('http://127.0.0.1:$port/$artifactName');
    final sha256Target = expectedSha256Bytes ?? artifactBytes;
    final sha256Hex = crypto.sha256.convert(sha256Target).toString();

    final platform = kind == 'dmg' ? 'macos' : 'windows';
    final installPolicy = switch (kind) {
      'dmg' => const ReleaseInstall(
        strategy: 'wholeBundleReplace',
        macosDmg: ReleaseMacOSDmgInstall(
          appBundleName: 'Thing.app',
          verifyPrimarySignature: true,
        ),
      ),
      'innoInstaller' => ReleaseInstall(
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
      _ => const ReleaseInstall(strategy: 'wholeDirectoryReplace'),
    };

    final placeholder = signingKey == null
        ? null
        : const ReleaseSignature(
            algorithm: 'ed25519',
            publicKeyId: _testKeyId,
            value: '',
          );

    final unsignedDescriptor = ReleaseDescriptor(
      schemaVersion: 3,
      packageId: 'local.munch.eventatlas',
      appName: 'Thing',
      version: '0.1.28',
      buildNumber: null,
      platform: platform,
      channel: 'stable',
      artifact: ReleaseArtifact(
        kind: kind,
        url: artifactUri,
        sha256: sha256Hex,
        length: overrideDescriptorLength ?? artifactBytes.length,
      ),
      install: installPolicy,
      signature: placeholder,
      minimumUpdaterVersion: '2.7.0',
      generatedAt: _testTimestamp,
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

    final signedDescriptor = ReleaseDescriptor(
      schemaVersion: unsignedDescriptor.schemaVersion,
      packageId: unsignedDescriptor.packageId,
      appName: unsignedDescriptor.appName,
      version: unsignedDescriptor.version,
      buildNumber: unsignedDescriptor.buildNumber,
      platform: unsignedDescriptor.platform,
      channel: unsignedDescriptor.channel,
      artifact: unsignedDescriptor.artifact,
      install: unsignedDescriptor.install,
      signature: signature,
      minimumUpdaterVersion: unsignedDescriptor.minimumUpdaterVersion,
      generatedAt: unsignedDescriptor.generatedAt,
    );

    final descriptorJson = jsonEncode(signedDescriptor.toJson());

    final fixture = _MockReleaseServer(
      server: server,
      artifactBytes: List.unmodifiable(artifactBytes),
      artifactName: artifactName,
      descriptorJson: descriptorJson,
      includeDescriptorAsset: includeDescriptorAsset,
    );

    server.listen((request) async {
      if (request.uri.path.endsWith(artifactName)) {
        fixture.artifactRequests++;
        request.response.headers.contentLength = fixture.artifactBytes.length;
        request.response.add(fixture.artifactBytes);
        await request.response.close();
      } else if (request.uri.path.endsWith('.release.json')) {
        fixture.descriptorRequests++;
        request.response.headers.contentType = io.ContentType.json;
        request.response.write(fixture.descriptorJson);
        await request.response.close();
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });

    return fixture;
  }

  Future<AppUpdateRelease> buildRelease() async {
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
          name: artifactName,
          downloadUrl: artifactUri,
          size: artifactBytes.length,
          sha256: '',
          descriptorUrl: includeDescriptorAsset ? descriptorUri : null,
        ),
      ],
    );
  }

  Future<void> close() => server.close(force: true);
}

class _ExitException implements Exception {
  const _ExitException();
}

Map<String, dynamic> _releaseJson({bool macAssets = false}) => {
  'tag_name': 'v0.1.5',
  'html_url': 'https://github.com/duochifan2003/Thing/releases/tag/v0.1.5',
  'body': '修复更新功能。',
  'assets': [
    _assetJson('Thing-windows-v0.1.19-setup.exe', size: 13177394),
    _assetJson('Thing-windows-v0.1.19-setup.exe.release.json', size: 512),
    _assetJson('Thing-windows-v0.1.19.zip', size: 15440124),
    _assetJson('Thing-windows-v0.1.19.zip.release.json', size: 512),
    if (macAssets) _assetJson('Thing-macOS-v0.1.19.dmg', size: 26523070),
    if (macAssets)
      _assetJson('Thing-macOS-v0.1.19.dmg.release.json', size: 512),
  ],
};

Map<String, dynamic> _assetJson(String name, {int size = 15440124}) => {
  'name': name,
  'browser_download_url':
      'https://github.com/duochifan2003/Thing/releases/download/v0.1.19/$name',
  'size': size,
};
