import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:desktop_updater/desktop_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:person_event_atlas/app_update.dart';

void main() {
  late SimpleKeyPair testKeyPair;
  late String testPublicKeyBase64;
  late Map<String, String> testPinnedKeys;
  final testTimestamp = DateTime.parse('2026-08-08T12:00:00Z');

  setUpAll(() async {
    final algorithm = Ed25519();
    testKeyPair = await algorithm.newKeyPair();
    final pubKey = await testKeyPair.extractPublicKey();
    testPublicKeyBase64 = base64Encode(pubKey.bytes);
    testPinnedKeys = {defaultReleasePublicKeyId: testPublicKeyBase64};
  });

  Future<ReleaseSignature> signDescriptor(
    ReleaseDescriptor descriptor, {
    SimpleKeyPair? keyPair,
    String publicKeyId = defaultReleasePublicKeyId,
  }) async {
    final algorithm = Ed25519();
    final signature = await algorithm.sign(
      descriptor.canonicalSignatureBytes(),
      keyPair: keyPair ?? testKeyPair,
    );
    return ReleaseSignature(
      algorithm: 'ed25519',
      publicKeyId: publicKeyId,
      value: base64Encode(signature.bytes),
    );
  }

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

  test('parses signatures from assets, signatures map, and release body', () {
    final release = AppUpdateRelease.fromJson({
      'tag_name': 'v0.1.28',
      'html_url': 'https://github.com/duochifan2003/Thing/releases/tag/v0.1.28',
      'published_at': '2026-08-08T12:00:00Z',
      'body': '''
## 更新说明
```json
{
  "signatures": {
    "Thing-windows-v0.1.28-setup.exe": "body-sig-value"
  }
}
```
''',
      'signatures': {
        'Thing-macOS-v0.1.28.dmg': {
          'algorithm': 'ed25519',
          'publicKeyId': 'thing-release-2026',
          'value': 'map-sig-value',
        },
      },
      'assets': [
        _assetJson(
          'Thing-macOS-v0.1.28.dmg',
          size: 25539642,
          digest:
              'sha256:e4b7dd225e926a9e0265e83c9771eda54a7ea1237ca44afba4b5f93d54366b1b',
        ),
        _assetJson(
          'Thing-windows-v0.1.28-setup.exe',
          size: 13199188,
          digest:
              'sha256:66ce35d639940b4a39f88bbd5b6b266db9e2e652f6b93b5faaf22b1169866326',
        ),
        {
          'name': 'Thing-direct.dmg',
          'browser_download_url':
              'https://github.com/duochifan2003/Thing/releases/download/v0.1.28/Thing-direct.dmg',
          'size': 12345,
          'digest':
              'sha256:08587106257237b90fc0c6f92ac5b43aeb7eb29105ec3dd0a16c5f0d0e1809a8',
          'signature': {
            'algorithm': 'ed25519',
            'publicKeyId': 'custom-key',
            'value': 'direct-sig-value',
          },
        },
      ],
    });

    final macAsset = release.assets.firstWhere(
      (a) => a.name == 'Thing-macOS-v0.1.28.dmg',
    );
    expect(macAsset.signature?.value, 'map-sig-value');
    expect(macAsset.signature?.publicKeyId, 'thing-release-2026');

    final winAsset = release.assets.firstWhere(
      (a) => a.name == 'Thing-windows-v0.1.28-setup.exe',
    );
    expect(winAsset.signature?.value, 'body-sig-value');

    final directAsset = release.assets.firstWhere(
      (a) => a.name == 'Thing-direct.dmg',
    );
    expect(directAsset.signature?.value, 'direct-sig-value');
    expect(directAsset.signature?.publicKeyId, 'custom-key');
  });

  test(
    'successfully downloads, verifies Ed25519 signature, stages, and installs macOS update',
    () async {
      String? stagedPathPassed;
      bool? allowUnsignedPassed;
      int? exitCodePassed;

      const payload = 'dummy-macos-dmg-content-bytes-12345';
      final payloadBytes = utf8.encode(payload);
      final expectedSha256 = crypto.sha256.convert(payloadBytes).toString();
      final expectedLength = payloadBytes.length;

      final protoDescriptor = ReleaseDescriptor(
        schemaVersion: 3,
        packageId: 'local.munch.eventatlas',
        appName: 'Thing',
        version: '0.1.28',
        buildNumber: null,
        platform: 'macos',
        channel: 'stable',
        artifact: ReleaseArtifact(
          kind: 'dmg',
          url: Uri.parse(
            'https://github.com/duochifan2003/Thing/releases/download/v0.1.28/Thing-macOS-v0.1.28.dmg',
          ),
          sha256: expectedSha256,
          length: expectedLength,
        ),
        install: const ReleaseInstall(
          strategy: 'wholeBundleReplace',
          macosDmg: ReleaseMacOSDmgInstall(
            appBundleName: 'Thing.app',
            verifyPrimarySignature: true,
          ),
        ),
        signature: const ReleaseSignature(
          algorithm: 'ed25519',
          publicKeyId: defaultReleasePublicKeyId,
          value: '',
        ),
        minimumUpdaterVersion: '2.7.0',
        generatedAt: testTimestamp,
      );

      final signature = await signDescriptor(protoDescriptor);

      final release = AppUpdateRelease(
        version: '0.1.28',
        tagName: 'v0.1.28',
        htmlUrl: Uri.parse(
          'https://github.com/duochifan2003/Thing/releases/tag/v0.1.28',
        ),
        notes: 'New release',
        generatedAt: testTimestamp,
        assets: [
          AppUpdateAsset(
            name: 'Thing-macOS-v0.1.28.dmg',
            downloadUrl: Uri.parse(
              'https://github.com/duochifan2003/Thing/releases/download/v0.1.28/Thing-macOS-v0.1.28.dmg',
            ),
            size: expectedLength,
            sha256: expectedSha256,
            signature: signature,
          ),
        ],
      );

      final service = AppUpdateService(
        currentVersion: '0.1.22',
        operatingSystem: 'macos',
        pinnedPublicKeys: testPinnedKeys,
        downloadUpdate:
            ({
              required appArchiveUrl,
              required currentVersion,
              required descriptor,
              onProgress,
            }) async {
              expect(
                descriptor.install.macosDmg?.verifyPrimarySignature,
                isTrue,
              );
              expect(descriptor.signature?.value, signature.value);
              onProgress?.call(expectedLength, expectedLength);
              return UpdateStageResult(
                descriptor: descriptor,
                stagingPath: '/tmp/test-stage/Thing.app',
              );
            },
        installUpdate:
            ({
              required stagingPath,
              removedFiles = const [],
              allowUnsignedMacOSUpdates = false,
              diagnosticsLogPath,
            }) async {
              stagedPathPassed = stagingPath;
              allowUnsignedPassed = allowUnsignedMacOSUpdates;
            },
        exitApp: (code) {
          exitCodePassed = code;
          throw const _ExitException();
        },
      );

      double? lastProgress;
      await expectLater(
        service.downloadAndInstall(
          release,
          onProgress: (p) => lastProgress = p,
        ),
        throwsA(isA<_ExitException>()),
      );

      expect(stagedPathPassed, '/tmp/test-stage/Thing.app');
      expect(
        allowUnsignedPassed,
        isFalse,
        reason: 'allowUnsignedMacOSUpdates must be false',
      );
      expect(exitCodePassed, 0);
      expect(lastProgress, 1.0);
    },
  );

  test(
    'successfully downloads and stages Windows Inno setup with required Authenticode policy',
    () async {
      String? stagedPathPassed;
      int? exitCodePassed;

      const payload = 'dummy-windows-exe-content-67890';
      final payloadBytes = utf8.encode(payload);
      final expectedSha256 = crypto.sha256.convert(payloadBytes).toString();
      final expectedLength = payloadBytes.length;

      const testThumbprints = [
        '961ADF40EB6795D3CC487D402D16D6C6247D503620E93BD3726AD72F7BC1B2D7',
      ];

      final protoDescriptor = ReleaseDescriptor(
        schemaVersion: 3,
        packageId: 'local.munch.eventatlas',
        appName: 'Thing',
        version: '0.1.28',
        buildNumber: null,
        platform: 'windows',
        channel: 'stable',
        artifact: ReleaseArtifact(
          kind: 'innoInstaller',
          url: Uri.parse(
            'https://github.com/duochifan2003/Thing/releases/download/v0.1.28/Thing-windows-v0.1.28-setup.exe',
          ),
          sha256: expectedSha256,
          length: expectedLength,
        ),
        install: const ReleaseInstall(
          strategy: 'innoInstaller',
          inno: ReleaseInnoInstall(
            silentArgs: ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
            inheritInstallDirectory: true,
            logFileName: 'thing-update.log',
            relaunchAfterInstall: true,
            requiresElevation: 'auto',
            authenticode: ReleaseAuthenticodePolicy(
              required: true,
              sha256Thumbprints: testThumbprints,
            ),
          ),
        ),
        signature: const ReleaseSignature(
          algorithm: 'ed25519',
          publicKeyId: defaultReleasePublicKeyId,
          value: '',
        ),
        minimumUpdaterVersion: '2.7.0',
        generatedAt: testTimestamp,
      );

      final signature = await signDescriptor(protoDescriptor);

      final release = AppUpdateRelease(
        version: '0.1.28',
        tagName: 'v0.1.28',
        htmlUrl: Uri.parse(
          'https://github.com/duochifan2003/Thing/releases/tag/v0.1.28',
        ),
        notes: 'New Windows release',
        generatedAt: testTimestamp,
        assets: [
          AppUpdateAsset(
            name: 'Thing-windows-v0.1.28-setup.exe',
            downloadUrl: Uri.parse(
              'https://github.com/duochifan2003/Thing/releases/download/v0.1.28/Thing-windows-v0.1.28-setup.exe',
            ),
            size: expectedLength,
            sha256: expectedSha256,
            signature: signature,
          ),
        ],
      );

      final service = AppUpdateService(
        currentVersion: '0.1.22',
        operatingSystem: 'windows',
        pinnedPublicKeys: testPinnedKeys,
        pinnedAuthenticodeThumbprints: testThumbprints,
        downloadUpdate:
            ({
              required appArchiveUrl,
              required currentVersion,
              required descriptor,
              onProgress,
            }) async {
              expect(descriptor.install.inno?.authenticode.required, isTrue);
              expect(
                descriptor.install.inno?.authenticode.sha256Thumbprints,
                testThumbprints,
              );
              return UpdateStageResult(
                descriptor: descriptor,
                stagingPath: '/tmp/test-stage/windows',
              );
            },
        installUpdate:
            ({
              required stagingPath,
              removedFiles = const [],
              allowUnsignedMacOSUpdates = false,
              diagnosticsLogPath,
            }) async {
              stagedPathPassed = stagingPath;
            },
        exitApp: (code) {
          exitCodePassed = code;
          throw const _ExitException();
        },
      );

      await expectLater(
        service.downloadAndInstall(release),
        throwsA(isA<_ExitException>()),
      );

      expect(stagedPathPassed, '/tmp/test-stage/windows');
      expect(exitCodePassed, 0);
    },
  );

  test('rejects update when asset has missing signature', () async {
    final release = AppUpdateRelease(
      version: '0.1.28',
      tagName: 'v0.1.28',
      htmlUrl: Uri.parse(
        'https://github.com/duochifan2003/Thing/releases/tag/v0.1.28',
      ),
      notes: 'Unsigned release',
      generatedAt: testTimestamp,
      assets: [
        AppUpdateAsset(
          name: 'Thing-macOS-v0.1.28.dmg',
          downloadUrl: Uri.parse(
            'https://github.com/duochifan2003/Thing/releases/download/v0.1.28/Thing-macOS-v0.1.28.dmg',
          ),
          size: 1000,
          sha256:
              '961adf40eb6795d3cc487d402d16d6c6247d503620e93bd3726ad72f7bc1b2d7',
          signature: null,
        ),
      ],
    );

    final service = AppUpdateService(
      currentVersion: '0.1.22',
      operatingSystem: 'macos',
      pinnedPublicKeys: testPinnedKeys,
    );

    await expectLater(
      service.downloadAndInstall(release),
      throwsA(
        isA<AppUpdateException>().having(
          (e) => e.message,
          'message',
          contains('缺少有效的发布签名'),
        ),
      ),
    );
  });

  test('rejects update when signature is invalid or forged', () async {
    const validSha =
        '961adf40eb6795d3cc487d402d16d6c6247d503620e93bd3726ad72f7bc1b2d7';

    // Signed with a different key pair
    final wrongKeyPair = await Ed25519().newKeyPair();
    final protoDescriptor = ReleaseDescriptor(
      schemaVersion: 3,
      packageId: 'local.munch.eventatlas',
      appName: 'Thing',
      version: '0.1.28',
      buildNumber: null,
      platform: 'macos',
      channel: 'stable',
      artifact: ReleaseArtifact(
        kind: 'dmg',
        url: Uri.parse(
          'https://github.com/duochifan2003/Thing/releases/download/v0.1.28/Thing-macOS-v0.1.28.dmg',
        ),
        sha256: validSha,
        length: 1000,
      ),
      install: const ReleaseInstall(
        strategy: 'wholeBundleReplace',
        macosDmg: ReleaseMacOSDmgInstall(
          appBundleName: 'Thing.app',
          verifyPrimarySignature: true,
        ),
      ),
      signature: const ReleaseSignature(
        algorithm: 'ed25519',
        publicKeyId: defaultReleasePublicKeyId,
        value: '',
      ),
      minimumUpdaterVersion: '2.7.0',
      generatedAt: testTimestamp,
    );

    final forgedSignature = await signDescriptor(
      protoDescriptor,
      keyPair: wrongKeyPair,
    );

    final release = AppUpdateRelease(
      version: '0.1.28',
      tagName: 'v0.1.28',
      htmlUrl: Uri.parse(
        'https://github.com/duochifan2003/Thing/releases/tag/v0.1.28',
      ),
      notes: 'Forged release',
      generatedAt: testTimestamp,
      assets: [
        AppUpdateAsset(
          name: 'Thing-macOS-v0.1.28.dmg',
          downloadUrl: Uri.parse(
            'https://github.com/duochifan2003/Thing/releases/download/v0.1.28/Thing-macOS-v0.1.28.dmg',
          ),
          size: 1000,
          sha256: validSha,
          signature: forgedSignature,
        ),
      ],
    );

    final service = AppUpdateService(
      currentVersion: '0.1.22',
      operatingSystem: 'macos',
      pinnedPublicKeys: testPinnedKeys,
    );

    await expectLater(
      service.downloadAndInstall(release),
      throwsA(
        isA<AppUpdateException>().having(
          (e) => e.message,
          'message',
          contains('签名校验失败'),
        ),
      ),
    );
  });

  test('rejects update when public key ID is not pinned/trusted', () async {
    const validSha =
        '961adf40eb6795d3cc487d402d16d6c6247d503620e93bd3726ad72f7bc1b2d7';

    final protoDescriptor = ReleaseDescriptor(
      schemaVersion: 3,
      packageId: 'local.munch.eventatlas',
      appName: 'Thing',
      version: '0.1.28',
      buildNumber: null,
      platform: 'macos',
      channel: 'stable',
      artifact: ReleaseArtifact(
        kind: 'dmg',
        url: Uri.parse(
          'https://github.com/duochifan2003/Thing/releases/download/v0.1.28/Thing-macOS-v0.1.28.dmg',
        ),
        sha256: validSha,
        length: 1000,
      ),
      install: const ReleaseInstall(
        strategy: 'wholeBundleReplace',
        macosDmg: ReleaseMacOSDmgInstall(
          appBundleName: 'Thing.app',
          verifyPrimarySignature: true,
        ),
      ),
      signature: const ReleaseSignature(
        algorithm: 'ed25519',
        publicKeyId: 'untrusted-key-id',
        value: '',
      ),
      minimumUpdaterVersion: '2.7.0',
      generatedAt: testTimestamp,
    );

    final signature = await signDescriptor(
      protoDescriptor,
      publicKeyId: 'untrusted-key-id',
    );

    final release = AppUpdateRelease(
      version: '0.1.28',
      tagName: 'v0.1.28',
      htmlUrl: Uri.parse(
        'https://github.com/duochifan2003/Thing/releases/tag/v0.1.28',
      ),
      notes: 'Untrusted key release',
      generatedAt: testTimestamp,
      assets: [
        AppUpdateAsset(
          name: 'Thing-macOS-v0.1.28.dmg',
          downloadUrl: Uri.parse(
            'https://github.com/duochifan2003/Thing/releases/download/v0.1.28/Thing-macOS-v0.1.28.dmg',
          ),
          size: 1000,
          sha256: validSha,
          signature: signature,
        ),
      ],
    );

    final service = AppUpdateService(
      currentVersion: '0.1.22',
      operatingSystem: 'macos',
      pinnedPublicKeys: testPinnedKeys,
    );

    await expectLater(
      service.downloadAndInstall(release),
      throwsA(
        isA<AppUpdateException>().having(
          (e) => e.message,
          'message',
          contains('未受信任的公钥'),
        ),
      ),
    );
  });

  test('rejects update when downloaded artifact digest is tampered', () async {
    const validSha =
        '961adf40eb6795d3cc487d402d16d6c6247d503620e93bd3726ad72f7bc1b2d7';

    final protoDescriptor = ReleaseDescriptor(
      schemaVersion: 3,
      packageId: 'local.munch.eventatlas',
      appName: 'Thing',
      version: '0.1.28',
      buildNumber: null,
      platform: 'macos',
      channel: 'stable',
      artifact: ReleaseArtifact(
        kind: 'dmg',
        url: Uri.parse(
          'https://github.com/duochifan2003/Thing/releases/download/v0.1.28/Thing-macOS-v0.1.28.dmg',
        ),
        sha256: validSha,
        length: 1000,
      ),
      install: const ReleaseInstall(
        strategy: 'wholeBundleReplace',
        macosDmg: ReleaseMacOSDmgInstall(
          appBundleName: 'Thing.app',
          verifyPrimarySignature: true,
        ),
      ),
      signature: const ReleaseSignature(
        algorithm: 'ed25519',
        publicKeyId: defaultReleasePublicKeyId,
        value: '',
      ),
      minimumUpdaterVersion: '2.7.0',
      generatedAt: testTimestamp,
    );

    final signature = await signDescriptor(protoDescriptor);

    final release = AppUpdateRelease(
      version: '0.1.28',
      tagName: 'v0.1.28',
      htmlUrl: Uri.parse(
        'https://github.com/duochifan2003/Thing/releases/tag/v0.1.28',
      ),
      notes: 'Tampered digest release',
      generatedAt: testTimestamp,
      assets: [
        AppUpdateAsset(
          name: 'Thing-macOS-v0.1.28.dmg',
          downloadUrl: Uri.parse(
            'https://github.com/duochifan2003/Thing/releases/download/v0.1.28/Thing-macOS-v0.1.28.dmg',
          ),
          size: 1000,
          sha256: validSha,
          signature: signature,
        ),
      ],
    );

    final service = AppUpdateService(
      currentVersion: '0.1.22',
      operatingSystem: 'macos',
      pinnedPublicKeys: testPinnedKeys,
      downloadUpdate:
          ({
            required appArchiveUrl,
            required currentVersion,
            required descriptor,
            onProgress,
          }) async {
            // Simulated verifier failure when actual file sha256 mismatch occurs
            throw const io.FileSystemException(
              'Artifact SHA-256 mismatch: expected 961a..., got fffff...',
              '/tmp/artifact.dmg',
            );
          },
    );

    await expectLater(
      service.downloadAndInstall(release),
      throwsA(
        isA<AppUpdateException>().having(
          (e) => e.message,
          'message',
          contains('完整性校验失败'),
        ),
      ),
    );
  });

  test(
    'verifyArtifactDigest helper correctly validates file length and SHA-256',
    () async {
      final tempDir = await io.Directory.systemTemp.createTemp(
        'thing-test-digest-',
      );
      try {
        final file = io.File('${tempDir.path}/test.bin');
        const content = 'thing-archive-test-content';
        final bytes = utf8.encode(content);
        await file.writeAsBytes(bytes);

        final correctDigest = crypto.sha256.convert(bytes).toString();

        // Valid match succeeds without exception
        await verifyArtifactDigest(
          file: file,
          expectedSha256: correctDigest,
          expectedLength: bytes.length,
        );

        // Wrong length throws
        expect(
          () => verifyArtifactDigest(
            file: file,
            expectedSha256: correctDigest,
            expectedLength: bytes.length + 1,
          ),
          throwsA(isA<io.FileSystemException>()),
        );

        // Tampered digest throws
        expect(
          () => verifyArtifactDigest(
            file: file,
            expectedSha256:
                '0000000000000000000000000000000000000000000000000000000000000000',
            expectedLength: bytes.length,
          ),
          throwsA(isA<io.FileSystemException>()),
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );
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
