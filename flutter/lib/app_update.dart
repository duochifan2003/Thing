import 'dart:convert';
import 'dart:io' as io;

import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:desktop_updater/desktop_updater.dart';

const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0');
const appBuild = String.fromEnvironment('APP_BUILD', defaultValue: '0');
const appVersionLabel = appVersion == '0.0.0'
    ? 'development'
    : 'v$appVersion+$appBuild';

const defaultReleasePublicKeyId = 'thing-release-2026';
const defaultReleasePublicKey = 'vX+FZ4m9LP6AvCFMDbmOzf89ziI5coXAxPE1dYpjpLA=';
const defaultPinnedReleasePublicKeys = <String, String>{
  defaultReleasePublicKeyId: defaultReleasePublicKey,
};

const configuredAuthenticodeThumbprint = String.fromEnvironment(
  'WINDOWS_AUTHENTICODE_SHA256',
);
final defaultPinnedAuthenticodeThumbprints =
    configuredAuthenticodeThumbprint.trim().isEmpty
    ? const <String>[]
    : <String>[configuredAuthenticodeThumbprint.trim()];

const _repository = 'duochifan2003/Thing';
const _latestReleaseUri =
    'https://api.github.com/repos/$_repository/releases/latest';

typedef UpdateProgress = void Function(double value);
typedef UpdateJsonFetcher = Future<String> Function(Uri uri);
typedef UpdateExit = Never Function(int code);
typedef UpdateInstaller = Future<void> Function(String stagingPath);

Future<bool> verifyReleaseSignature({
  required ReleaseDescriptor descriptor,
  required Map<String, String> publicKeys,
  Ed25519? algorithm,
}) async {
  final signature = descriptor.signature;
  if (signature == null ||
      signature.algorithm != 'ed25519' ||
      signature.publicKeyId.trim().isEmpty ||
      signature.value.trim().isEmpty) {
    return false;
  }
  final publicKeyValue = publicKeys[signature.publicKeyId];
  if (publicKeyValue == null || publicKeyValue.trim().isEmpty) return false;

  try {
    final publicKey = SimplePublicKey(
      base64Decode(publicKeyValue.trim()),
      type: KeyPairType.ed25519,
    );
    return await (algorithm ?? Ed25519()).verify(
      descriptor.canonicalSignatureBytes(),
      signature: Signature(
        base64Decode(signature.value.trim()),
        publicKey: publicKey,
      ),
    );
  } on Object {
    return false;
  }
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppUpdateAsset {
  const AppUpdateAsset({
    required this.name,
    required this.downloadUrl,
    this.size = 0,
    this.sha256 = '',
    this.signature,
  });

  final String name;
  final Uri downloadUrl;
  final int size;
  final String sha256;
  final ReleaseSignature? signature;
}

class AppUpdateRelease {
  AppUpdateRelease({
    required this.version,
    required this.tagName,
    required this.htmlUrl,
    required this.notes,
    required this.assets,
    this.signature,
    DateTime? generatedAt,
  }) : generatedAt =
           generatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  final String version;
  final String tagName;
  final Uri htmlUrl;
  final String notes;
  final List<AppUpdateAsset> assets;
  final ReleaseSignature? signature;
  final DateTime generatedAt;

  AppUpdateAsset? assetFor(String operatingSystem) {
    final candidates = assets.where((asset) {
      final name = asset.name.toLowerCase();
      return switch (operatingSystem) {
        'macos' =>
          name.contains('macos') &&
              (name.endsWith('.dmg') || name.endsWith('.zip')),
        'windows' =>
          name.contains('windows') &&
              (name.endsWith('.zip') || name.endsWith('.exe')),
        _ => false,
      };
    }).toList();
    if (candidates.isEmpty) return null;
    if (operatingSystem == 'macos') {
      return candidates.firstWhere(
        (asset) => asset.name.toLowerCase().endsWith('.dmg'),
        orElse: () => candidates.first,
      );
    }
    return candidates.firstWhere(
      (asset) => asset.name.toLowerCase().endsWith('-setup.exe'),
      orElse: () => candidates.first,
    );
  }

  factory AppUpdateRelease.fromJson(Map<String, dynamic> json) {
    final tagName = json['tag_name'];
    final htmlUrl = json['html_url'];
    if (tagName is! String || htmlUrl is! String) {
      throw const FormatException('GitHub 更新信息格式不完整。');
    }
    final releaseUrl = Uri.tryParse(htmlUrl);
    if (releaseUrl == null || !_isAllowedGitHubUri(releaseUrl)) {
      throw const FormatException('GitHub 更新地址无效。');
    }
    final topSignature = _parseSignature(json['signature']);
    final signatures = _parseSignaturesMap(json['signatures']);
    final bodySignatures = _parseSignaturesFromBody(json['body']);
    final generatedAt =
        DateTime.tryParse(
          json['published_at'] as String? ??
              json['created_at'] as String? ??
              json['generated_at'] as String? ??
              '',
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final assets = <AppUpdateAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final rawAsset in rawAssets) {
        if (rawAsset is! Map) continue;
        final name = rawAsset['name'];
        final downloadUrl = rawAsset['browser_download_url'];
        if (name is! String || downloadUrl is! String) continue;
        final uri = Uri.tryParse(downloadUrl);
        if (uri == null || !_isAllowedGitHubUri(uri)) continue;
        final digest = rawAsset['digest'];
        final signature =
            _parseSignature(rawAsset['signature']) ??
            signatures[name] ??
            signatures[name.toLowerCase()] ??
            bodySignatures[name] ??
            bodySignatures[name.toLowerCase()] ??
            bodySignatures['*'] ??
            topSignature;
        assets.add(
          AppUpdateAsset(
            name: name,
            downloadUrl: uri,
            size: rawAsset['size'] is int ? rawAsset['size'] as int : 0,
            sha256: digest is String && digest.startsWith('sha256:')
                ? digest.substring('sha256:'.length).toLowerCase()
                : rawAsset['sha256'] is String
                ? (rawAsset['sha256'] as String).toLowerCase()
                : '',
            signature: signature,
          ),
        );
      }
    }
    return AppUpdateRelease(
      version: _normalizeVersion(tagName),
      tagName: tagName,
      htmlUrl: releaseUrl,
      notes: json['body'] is String ? json['body'] as String : '',
      assets: assets,
      signature: topSignature,
      generatedAt: generatedAt,
    );
  }
}

ReleaseSignature? _parseSignature(Object? value) {
  if (value is! Map) return null;
  return ReleaseSignature.fromJson(Map<String, dynamic>.from(value));
}

Map<String, ReleaseSignature> _parseSignaturesMap(Object? value) {
  if (value is! Map) return const {};
  final signatures = <String, ReleaseSignature>{};
  for (final entry in value.entries) {
    final name = entry.key.toString().trim();
    final signature = _parseSignature(entry.value);
    if (name.isNotEmpty && signature != null) signatures[name] = signature;
  }
  return signatures;
}

Map<String, ReleaseSignature> _parseSignaturesFromBody(Object? body) {
  if (body is! String || body.isEmpty) return const {};
  final blocks = RegExp(
    r'```(?:json)?\s*([\s\S]*?)\s*```',
    caseSensitive: false,
  ).allMatches(body);
  final signatures = <String, ReleaseSignature>{};
  for (final block in blocks) {
    try {
      final decoded = jsonDecode(block.group(1)!);
      if (decoded is Map) {
        signatures.addAll(_parseSignaturesMap(decoded['signatures']));
        final topSig = _parseSignature(decoded['signature']);
        if (topSig != null && !signatures.containsKey('*')) {
          signatures['*'] = topSig;
        }
        if (decoded['release'] is Map) {
          final rel = Map<String, dynamic>.from(decoded['release'] as Map);
          signatures.addAll(_parseSignaturesMap(rel['signatures']));
          final relSig = _parseSignature(rel['signature']);
          if (relSig != null && !signatures.containsKey('*')) {
            signatures['*'] = relSig;
          }
        }
      }
    } on Object {
      continue;
    }
  }
  return signatures;
}

class AppUpdateService {
  AppUpdateService({
    this.currentVersion = appVersion,
    String? operatingSystem,
    UpdateJsonFetcher? fetchJson,
    UpdateExit? exitApp,
    UpdateInstaller? installUpdate,
    Map<String, String>? pinnedPublicKeys,
    List<String>? pinnedAuthenticodeThumbprints,
  }) : operatingSystem = operatingSystem ?? io.Platform.operatingSystem,
       _fetchJson = fetchJson,
       _exitApp = exitApp ?? io.exit,
       _installUpdate = installUpdate,
       _pinnedPublicKeys = Map.unmodifiable(
         pinnedPublicKeys ?? defaultPinnedReleasePublicKeys,
       ),
       _pinnedAuthenticodeThumbprints = List.unmodifiable(
         pinnedAuthenticodeThumbprints ?? defaultPinnedAuthenticodeThumbprints,
       );

  final String currentVersion;
  final String operatingSystem;
  final UpdateJsonFetcher? _fetchJson;
  final UpdateExit _exitApp;
  final UpdateInstaller? _installUpdate;
  final Map<String, String> _pinnedPublicKeys;
  final List<String> _pinnedAuthenticodeThumbprints;

  Future<AppUpdateRelease?> checkForUpdate() async {
    final source = _fetchJson ?? _fetchLatestRelease;
    final raw = await source(Uri.parse(_latestReleaseUri));
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const AppUpdateException('GitHub 更新信息无法解析。');
    }
    final release = AppUpdateRelease.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    if (!_isNewerVersion(release.version, currentVersion)) return null;
    if (release.assetFor(operatingSystem) == null) {
      throw AppUpdateException('GitHub 最新版本 ${release.tagName} 没有适用于当前系统的安装包。');
    }
    return release;
  }

  Future<void> downloadAndInstall(
    AppUpdateRelease release, {
    UpdateProgress? onProgress,
  }) async {
    final asset = release.assetFor(operatingSystem);
    if (asset == null) {
      throw const AppUpdateException('当前系统没有可用的更新包。');
    }
    if (operatingSystem != 'macos' && operatingSystem != 'windows') {
      throw const AppUpdateException('当前系统暂不支持自动安装更新。');
    }
    if (asset.size <= 0 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(asset.sha256)) {
      throw const AppUpdateException('GitHub 更新包缺少有效的 SHA-256 校验信息。');
    }

    try {
      final descriptor = ReleaseDescriptor(
        schemaVersion: 3,
        packageId: 'local.munch.eventatlas',
        appName: 'Thing',
        version: release.version,
        buildNumber: null,
        platform: operatingSystem,
        channel: 'stable',
        artifact: ReleaseArtifact(
          kind: _artifactKind(asset),
          url: asset.downloadUrl,
          sha256: asset.sha256,
          length: asset.size,
        ),
        install: _installMetadata(asset),
        signature: asset.signature ?? release.signature,
        minimumUpdaterVersion: '2.7.0',
        generatedAt: release.generatedAt,
      );
      if (!await verifyReleaseSignature(
        descriptor: descriptor,
        publicKeys: _pinnedPublicKeys,
      )) {
        throw const AppUpdateException('更新校验失败：签名或签名描述无效。');
      }
      final staged = await DesktopUpdater().downloadZipFirstUpdate(
        appArchiveUrl: Uri.parse(_latestReleaseUri),
        currentVersion: DesktopVersionInfo.parse(currentVersion),
        descriptor: descriptor,
        onProgress: (received, total) {
          if (total != null && total > 0) onProgress?.call(received / total);
        },
      );
      onProgress?.call(1);
      final installer = _installUpdate;
      if (installer != null) {
        await installer(staged.stagingPath);
      } else {
        await DesktopUpdater().installUpdate(
          stagingPath: staged.stagingPath,
          allowUnsignedMacOSUpdates: false,
        );
      }
    } on AppUpdateException {
      rethrow;
    } on io.FileSystemException catch (error) {
      throw AppUpdateException('更新包完整性校验失败：${error.message}');
    } on FormatException catch (error) {
      throw AppUpdateException('更新描述校验失败：${error.message}');
    } on Object catch (error) {
      throw AppUpdateException('更新安装失败：$error');
    }
    _exitApp(0);
  }

  String _artifactKind(AppUpdateAsset asset) {
    final name = asset.name.toLowerCase();
    if (operatingSystem == 'macos' && name.endsWith('.dmg')) return 'dmg';
    if (operatingSystem == 'windows' && name.endsWith('.exe')) {
      return 'innoInstaller';
    }
    return 'zip';
  }

  ReleaseInstall _installMetadata(AppUpdateAsset asset) {
    switch (_artifactKind(asset)) {
      case 'dmg':
        return const ReleaseInstall(
          strategy: 'wholeBundleReplace',
          macosDmg: ReleaseMacOSDmgInstall(
            appBundleName: 'Thing.app',
            verifyPrimarySignature: true,
          ),
        );
      case 'innoInstaller':
        if (_pinnedAuthenticodeThumbprints.isEmpty) {
          throw const AppUpdateException(
            '未配置 Windows Authenticode 证书指纹 (WINDOWS_AUTHENTICODE_SHA256)，拒绝执行未受信任的安装程序更新。',
          );
        }
        for (final thumbprint in _pinnedAuthenticodeThumbprints) {
          if (!RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(thumbprint)) {
            throw const AppUpdateException(
              'Windows Authenticode 证书指纹格式无效（必须为 64 位十六进制字符）。',
            );
          }
        }
        return ReleaseInstall(
          strategy: 'innoInstaller',
          inno: ReleaseInnoInstall(
            silentArgs: ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
            inheritInstallDirectory: true,
            logFileName: 'thing-update.log',
            relaunchAfterInstall: true,
            requiresElevation: 'auto',
            authenticode: ReleaseAuthenticodePolicy(
              required: true,
              sha256Thumbprints: _pinnedAuthenticodeThumbprints,
            ),
          ),
        );
      default:
        return const ReleaseInstall(strategy: 'wholeDirectoryReplace');
    }
  }

  Future<String> _fetchLatestRelease(Uri uri) async {
    final client = io.HttpClient()..userAgent = 'Thing/$currentVersion';
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        io.HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != io.HttpStatus.ok) {
        if (response.statusCode == io.HttpStatus.notFound) {
          throw const AppUpdateException(
            '无法读取 GitHub 更新源。仓库可能是私有的，请公开仓库或配置访问令牌。',
          );
        }
        throw AppUpdateException('GitHub 更新检查失败（HTTP ${response.statusCode}）。');
      }
      return body;
    } on AppUpdateException {
      rethrow;
    } on io.SocketException {
      throw const AppUpdateException('无法连接 GitHub，请检查网络后重试。');
    } finally {
      client.close(force: true);
    }
  }
}

String _normalizeVersion(String value) {
  final normalized = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final match = RegExp(r'^\d+(?:\.\d+){0,3}').firstMatch(normalized);
  return match?.group(0) ?? '0.0.0';
}

bool _isNewerVersion(String candidate, String current) {
  final left = _versionParts(candidate);
  final right = _versionParts(current);
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return left[index] > right[index];
  }
  return false;
}

List<int> _versionParts(String value) {
  final parts = _normalizeVersion(value).split('.').map(int.parse).toList();
  while (parts.length < 4) {
    parts.add(0);
  }
  return parts;
}

bool isNewerAppVersion(String candidate, String current) =>
    _isNewerVersion(candidate, current);

bool _isAllowedGitHubUri(Uri uri) =>
    uri.scheme == 'https' &&
    (uri.host == 'github.com' || uri.host.endsWith('.githubusercontent.com'));
