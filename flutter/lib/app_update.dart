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
typedef UpdateStager =
    Future<UpdateStageResult> Function({
      required Uri appArchiveUrl,
      required DesktopVersionInfo currentVersion,
      required ReleaseDescriptor descriptor,
      void Function(int receivedBytes, int? totalBytes)? onProgress,
    });

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
    this.descriptorUrl,
    this.descriptor,
  });

  final String name;
  final Uri downloadUrl;
  final int size;
  final String sha256;
  final Uri? descriptorUrl;
  final ReleaseDescriptor? descriptor;
}

class AppUpdateRelease {
  AppUpdateRelease({
    required this.version,
    required this.tagName,
    required this.htmlUrl,
    required this.notes,
    required this.assets,
    DateTime? generatedAt,
  }) : generatedAt =
           generatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  final String version;
  final String tagName;
  final Uri htmlUrl;
  final String notes;
  final List<AppUpdateAsset> assets;
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

    final descriptorUrls = <String, Uri>{};
    final rawAssetList = <Map<String, dynamic>>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final raw in rawAssets) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final name = map['name'];
        final downloadUrl = map['browser_download_url'];
        if (name is! String || downloadUrl is! String) continue;
        final uri = Uri.tryParse(downloadUrl);
        if (uri == null || !_isAllowedGitHubUri(uri)) continue;

        if (name.endsWith('.release.json')) {
          final targetName = name.substring(
            0,
            name.length - '.release.json'.length,
          );
          descriptorUrls[targetName] = uri;
        } else {
          rawAssetList.add(map);
        }
      }
    }

    final assets = <AppUpdateAsset>[];
    for (final map in rawAssetList) {
      final name = map['name'] as String;
      final uri = Uri.parse(map['browser_download_url'] as String);
      final size = map['size'] is int ? map['size'] as int : 0;
      final digestRaw = map['digest'] as String? ?? '';
      final sha256 = digestRaw
          .replaceFirst(RegExp(r'^sha256:', caseSensitive: false), '')
          .trim()
          .toLowerCase();
      final descriptorUrl = descriptorUrls[name];
      ReleaseDescriptor? descriptor;
      if (map['descriptor'] is Map) {
        descriptor = ReleaseDescriptor.fromJson(
          Map<String, dynamic>.from(map['descriptor'] as Map),
        );
      }
      assets.add(
        AppUpdateAsset(
          name: name,
          downloadUrl: uri,
          size: size,
          sha256: sha256,
          descriptorUrl: descriptorUrl,
          descriptor: descriptor,
        ),
      );
    }

    final version = _normalizeVersion(tagName);
    final notes = json['body'] as String? ?? '';
    final generatedAt =
        DateTime.tryParse(
          json['published_at'] as String? ??
              json['created_at'] as String? ??
              json['generated_at'] as String? ??
              '',
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    return AppUpdateRelease(
      version: version,
      tagName: tagName,
      htmlUrl: releaseUrl,
      notes: notes,
      assets: assets,
      generatedAt: generatedAt,
    );
  }
}

class AppUpdateService {
  AppUpdateService({
    this.currentVersion = appVersion,
    String? operatingSystem,
    UpdateJsonFetcher? fetchJson,
    UpdateExit? exitApp,
    UpdateInstaller? installUpdate,
    UpdateStager? stageUpdate,
    Map<String, String>? pinnedPublicKeys,
    List<String>? pinnedAuthenticodeThumbprints,
  }) : operatingSystem = operatingSystem ?? io.Platform.operatingSystem,
       _fetchJson = fetchJson,
       _exitApp = exitApp ?? io.exit,
       _installUpdate = installUpdate,
       _stageUpdate = stageUpdate,
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
  final UpdateStager? _stageUpdate;
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

    ReleaseDescriptor descriptor;
    if (asset.descriptor != null) {
      descriptor = asset.descriptor!;
    } else if (asset.descriptorUrl != null) {
      final source = _fetchJson ?? _fetchLatestRelease;
      final descriptorRaw = await source(asset.descriptorUrl!);
      final decoded = jsonDecode(descriptorRaw);
      if (decoded is! Map) {
        throw const AppUpdateException('签名描述文件格式无效。');
      }
      try {
        descriptor = ReleaseDescriptor.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      } on Object catch (e) {
        throw AppUpdateException('签名描述文件解析失败：$e');
      }
    } else {
      throw AppUpdateException(
        'GitHub 更新包缺少对应的签名描述文件 (${asset.name}.release.json)。',
      );
    }

    if (descriptor.schemaVersion != 3) {
      throw const AppUpdateException('签名描述版本不支持（必须为 schemaVersion 3）。');
    }
    if (descriptor.packageId != 'local.munch.eventatlas' ||
        descriptor.appName != 'Thing') {
      throw const AppUpdateException('签名描述包标识或应用名称不匹配。');
    }
    if (descriptor.platform != operatingSystem) {
      throw const AppUpdateException('签名描述目标平台与当前系统不匹配。');
    }
    if (descriptor.channel != 'stable') {
      throw const AppUpdateException('签名描述发布通道无效。');
    }
    if (descriptor.minimumUpdaterVersion != '2.7.0') {
      throw const AppUpdateException('更新器最低版本要求不匹配。');
    }
    if (_normalizeVersion(descriptor.version) !=
        _normalizeVersion(release.version)) {
      throw const AppUpdateException('签名描述版本与 Release 版本不一致。');
    }
    if (descriptor.artifact.url != asset.downloadUrl) {
      throw const AppUpdateException('签名描述中的下载地址与 Release 资产地址不一致。');
    }
    if (asset.size > 0 && descriptor.artifact.length != asset.size) {
      throw const AppUpdateException('签名描述中的文件大小与 Release 资产大小不一致。');
    }
    final expectedSha256 = descriptor.artifact.sha256.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256)) {
      throw const AppUpdateException('签名描述中缺少有效的 SHA-256 校验信息。');
    }
    if (asset.sha256.isNotEmpty && asset.sha256 != expectedSha256) {
      throw const AppUpdateException('Release 资产 digest 与签名描述 SHA-256 不一致。');
    }

    if (operatingSystem == 'windows') {
      if (descriptor.artifact.kind == 'innoInstaller') {
        final inno = descriptor.install.inno;
        if (descriptor.install.strategy != 'innoInstaller' || inno == null) {
          throw const AppUpdateException('Windows 安装程序策略不匹配。');
        }
        if (!inno.authenticode.required) {
          throw const AppUpdateException('Windows 安装程序必须启用 Authenticode 签名校验。');
        }
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
          if (!inno.authenticode.sha256Thumbprints.any(
            (t) => t.toLowerCase() == thumbprint.toLowerCase(),
          )) {
            throw const AppUpdateException('签名描述 Authenticode 指纹与客户端固定指纹不匹配。');
          }
        }
      } else if (descriptor.artifact.kind == 'zip') {
        if (descriptor.install.strategy != 'wholeDirectoryReplace') {
          throw const AppUpdateException('Windows ZIP 更新策略不匹配。');
        }
      } else {
        throw AppUpdateException(
          '不支持的 Windows 产物类型：${descriptor.artifact.kind}。',
        );
      }
    } else if (operatingSystem == 'macos') {
      if (descriptor.artifact.kind != 'dmg' &&
          descriptor.artifact.kind != 'zip') {
        throw AppUpdateException(
          '不支持的 macOS 产物类型：${descriptor.artifact.kind}。',
        );
      }
      if (descriptor.artifact.kind == 'dmg') {
        final macosDmg = descriptor.install.macosDmg;
        if (descriptor.install.strategy != 'wholeBundleReplace' ||
            macosDmg == null ||
            macosDmg.appBundleName != 'Thing.app' ||
            !macosDmg.verifyPrimarySignature) {
          throw const AppUpdateException('macOS DMG 更新策略无效（必须启用主签名校验）。');
        }
      }
    }

    if (!await verifyReleaseSignature(
      descriptor: descriptor,
      publicKeys: _pinnedPublicKeys,
    )) {
      throw const AppUpdateException('更新校验失败：签名或签名描述无效。');
    }

    try {
      final stager = _stageUpdate ?? DesktopUpdater().downloadZipFirstUpdate;
      final staged = await stager(
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
