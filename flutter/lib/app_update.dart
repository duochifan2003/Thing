import 'dart:convert';
import 'dart:io' as io;

import 'package:desktop_updater/desktop_updater.dart';

const appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.30',
);
const appBuild = String.fromEnvironment('APP_BUILD', defaultValue: '53');
const appVersionLabel = 'v$appVersion+$appBuild';

const _repository = 'duochifan2003/Thing';
const _latestReleaseUri =
    'https://api.github.com/repos/$_repository/releases/latest';

typedef UpdateProgress = void Function(double value);
typedef UpdateJsonFetcher = Future<String> Function(Uri uri);
typedef UpdateExit = Never Function(int code);

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
  });

  final String name;
  final Uri downloadUrl;
  final int size;
  final String sha256;
}

class AppUpdateRelease {
  const AppUpdateRelease({
    required this.version,
    required this.tagName,
    required this.htmlUrl,
    required this.notes,
    required this.assets,
  });

  final String version;
  final String tagName;
  final Uri htmlUrl;
  final String notes;
  final List<AppUpdateAsset> assets;

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
        assets.add(
          AppUpdateAsset(
            name: name,
            downloadUrl: uri,
            size: rawAsset['size'] is int ? rawAsset['size'] as int : 0,
            sha256: digest is String && digest.startsWith('sha256:')
                ? digest.substring('sha256:'.length).toLowerCase()
                : '',
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
    );
  }
}

class AppUpdateService {
  AppUpdateService({
    this.currentVersion = appVersion,
    String? operatingSystem,
    UpdateJsonFetcher? fetchJson,
    UpdateExit? exitApp,
  }) : operatingSystem = operatingSystem ?? io.Platform.operatingSystem,
       _fetchJson = fetchJson,
       _exitApp = exitApp ?? io.exit;

  final String currentVersion;
  final String operatingSystem;
  final UpdateJsonFetcher? _fetchJson;
  final UpdateExit _exitApp;

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
      minimumUpdaterVersion: '2.7.0',
      generatedAt: DateTime.now().toUtc(),
    )..validate();

    try {
      final staged = await DesktopUpdater().downloadZipFirstUpdate(
        appArchiveUrl: Uri.parse(_latestReleaseUri),
        currentVersion: DesktopVersionInfo.parse(currentVersion),
        descriptor: descriptor,
        onProgress: (received, total) {
          if (total != null && total > 0) onProgress?.call(received / total);
        },
      );
      onProgress?.call(1);
      await DesktopUpdater().installUpdate(
        stagingPath: staged.stagingPath,
        allowUnsignedMacOSUpdates: true,
      );
    } on AppUpdateException {
      rethrow;
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
            verifyPrimarySignature: false,
          ),
        );
      case 'innoInstaller':
        return const ReleaseInstall(
          strategy: 'innoInstaller',
          inno: ReleaseInnoInstall(
            silentArgs: ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
            inheritInstallDirectory: true,
            logFileName: 'thing-update.log',
            relaunchAfterInstall: true,
            requiresElevation: 'auto',
            authenticode: ReleaseAuthenticodePolicy(required: false),
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
