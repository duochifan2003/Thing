// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io' as io;

import 'package:desktop_updater/desktop_updater.dart';
import 'package:desktop_updater/src/core/macos_distribution_artifacts.dart'
    show MacOSDistributionVerifier, MountedDmg;
import 'package:desktop_updater/src/core/update_client.dart' show UpdateClient;
import 'package:desktop_updater/src/macos_update.dart'
    show defaultProcessRunner;

const appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.22',
);
const appBuild = String.fromEnvironment('APP_BUILD', defaultValue: '45');
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
        (asset) => asset.name.toLowerCase().endsWith('.zip'),
        orElse: () => candidates.first,
      );
    }
    return candidates.firstWhere(
      (asset) =>
          asset.name.toLowerCase().endsWith('-setup.exe') ||
          asset.name.toLowerCase().endsWith('.exe'),
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
    final body = json['body'] is String ? json['body'] as String : '';
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
        final sha256 = _findSha256(rawAsset, name, body);
        assets.add(
          AppUpdateAsset(
            name: name,
            downloadUrl: uri,
            size: rawAsset['size'] is int ? rawAsset['size'] as int : 0,
            sha256: sha256,
          ),
        );
      }
    }
    return AppUpdateRelease(
      version: _normalizeVersion(tagName),
      tagName: tagName,
      htmlUrl: releaseUrl,
      notes: body,
      assets: assets,
    );
  }
}

/// Uses the current macOS image command and retains a narrow old-system fallback.
class MacOSDmgMountAdapter extends MacOSDistributionVerifier {
  MacOSDmgMountAdapter({super.runProcess = defaultProcessRunner});

  @override
  Future<MountedDmg> mountDmgReadOnly({required io.File dmg}) async {
    const diskutil = '/usr/sbin/diskutil';
    final arguments = [
      'image',
      'attach',
      '--readOnly',
      '--mountOptions',
      'nobrowse',
      dmg.path,
    ];
    io.ProcessResult result;
    try {
      result = await runProcess(diskutil, arguments);
    } on io.ProcessException catch (error) {
      return _attachWithHdiutil(dmg, 'diskutil 不可用：$error');
    } on Object catch (error) {
      throw AppUpdateException('更新包挂载失败：$error');
    }

    if (result.exitCode == 0) return _mountedDmg(dmg, result.stdout.toString());
    if (_isUnsupportedDiskutil(result)) {
      return _attachWithHdiutil(dmg, _processDetails(result));
    }
    throw AppUpdateException(
      '更新包挂载失败：diskutil image attach 失败：${_processDetails(result)}',
    );
  }

  @override
  Future<void> detachDmg(MountedDmg mounted) async {
    io.ProcessResult result;
    try {
      result = await runProcess('/usr/sbin/diskutil', [
        'eject',
        mounted.mountPoint,
      ]);
    } on Object catch (error) {
      throw AppUpdateException('更新包卸载失败：$error');
    }
    if (result.exitCode != 0) {
      throw AppUpdateException('更新包卸载失败：${_processDetails(result)}');
    }
  }

  Future<MountedDmg> _attachWithHdiutil(io.File dmg, String reason) async {
    io.ProcessResult result;
    try {
      result = await runProcess('/usr/bin/hdiutil', [
        'attach',
        '-readonly',
        '-nobrowse',
        dmg.path,
      ]);
    } on Object catch (error) {
      throw AppUpdateException('更新包挂载失败：diskutil 不可用（$reason），兼容回退也失败：$error');
    }
    if (result.exitCode != 0) {
      throw AppUpdateException(
        '更新包挂载失败：diskutil 不可用（$reason），兼容回退失败：${_processDetails(result)}',
      );
    }
    return _mountedDmg(dmg, result.stdout.toString());
  }

  MountedDmg _mountedDmg(io.File dmg, String output) {
    final mountPoint = _mountPointFromOutput(output);
    if (mountPoint == null) {
      throw const AppUpdateException('更新包挂载失败：macOS 未返回挂载目录。');
    }
    return MountedDmg(imagePath: dmg.path, mountPoint: mountPoint);
  }
}

class _ThingDesktopUpdater extends DesktopUpdater {
  @override
  Future<UpdateStageResult> downloadZipFirstUpdate({
    required Uri appArchiveUrl,
    required DesktopVersionInfo currentVersion,
    required ReleaseDescriptor descriptor,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    UpdateRequestHeadersProvider? requestHeadersProvider,
  }) {
    if (descriptor.platform != 'macos') {
      return super.downloadZipFirstUpdate(
        appArchiveUrl: appArchiveUrl,
        currentVersion: currentVersion,
        descriptor: descriptor,
        onProgress: onProgress,
        requestHeadersProvider: requestHeadersProvider,
      );
    }
    return UpdateClient(
      appArchiveUrl: appArchiveUrl,
      currentVersion: currentVersion,
      requestHeadersProvider: requestHeadersProvider,
      macosDistributionVerifier: MacOSDmgMountAdapter(),
    ).downloadVerifyAndStage(descriptor: descriptor, onProgress: onProgress);
  }
}

String _findSha256(Map rawAsset, String assetName, String body) {
  final digest = rawAsset['digest'];
  if (digest is String && digest.startsWith('sha256:')) {
    final hash = digest.substring('sha256:'.length).trim().toLowerCase();
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) return hash;
  }
  final sha256Field = rawAsset['sha256'];
  if (sha256Field is String) {
    final hash = sha256Field.trim().toLowerCase();
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) return hash;
  }
  final escapedName = RegExp.escape(assetName);
  final patterns = [
    RegExp('([0-9a-fA-F]{64})\\s+[*]?$escapedName'),
    RegExp('$escapedName\\s*[:=]\\s*([0-9a-fA-F]{64})'),
    RegExp(
      'SHA-?256\\s*\\($escapedName\\)\\s*=\\s*([0-9a-fA-F]{64})',
      caseSensitive: false,
    ),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(body);
    if (match != null) {
      return match.group(1)!.toLowerCase();
    }
  }
  return '';
}

class AppUpdateService {
  AppUpdateService({
    this.currentVersion = appVersion,
    String? operatingSystem,
    UpdateJsonFetcher? fetchJson,
    UpdateExit? exitApp,
    DesktopUpdater? desktopUpdater,
  }) : operatingSystem = operatingSystem ?? io.Platform.operatingSystem,
       _fetchJson = fetchJson,
       _exitApp = exitApp ?? io.exit,
       _desktopUpdater = desktopUpdater ?? _ThingDesktopUpdater();

  final String currentVersion;
  final String operatingSystem;
  final UpdateJsonFetcher? _fetchJson;
  final UpdateExit _exitApp;
  final DesktopUpdater _desktopUpdater;

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
    if (asset.size <= 0) {
      throw const AppUpdateException('GitHub 更新包大小无效。');
    }
    if (asset.sha256.isEmpty ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(asset.sha256)) {
      throw const AppUpdateException('GitHub 更新包缺少有效的 SHA-256 校验信息。');
    }

    final descriptor = ReleaseDescriptor(
      schemaVersion: 3,
      packageId: 'local.munch.eventatlas',
      appName: operatingSystem == 'macos' ? 'Thing.app' : 'Thing',
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

    late final UpdateStageResult staged;
    try {
      staged = await _desktopUpdater.downloadZipFirstUpdate(
        appArchiveUrl: Uri.parse(_latestReleaseUri),
        currentVersion: DesktopVersionInfo.parse(currentVersion),
        descriptor: descriptor,
        onProgress: (received, total) {
          if (total != null && total > 0) onProgress?.call(received / total);
        },
      );
      onProgress?.call(1);
    } on AppUpdateException {
      rethrow;
    } on io.FileSystemException catch (error) {
      final detail = error.message;
      if (detail.contains('Artifact length mismatch') ||
          detail.contains('Artifact SHA-256 mismatch')) {
        throw AppUpdateException('更新校验失败：$detail');
      }
      throw AppUpdateException('更新下载失败：$detail');
    } on io.SocketException catch (error) {
      throw AppUpdateException('更新下载失败：$error');
    } on io.HttpException catch (error) {
      throw AppUpdateException('更新下载失败：$error');
    } on Object catch (error) {
      throw AppUpdateException('更新下载失败：$error');
    }

    try {
      await _desktopUpdater.installUpdate(
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
    } on io.HttpException {
      throw const AppUpdateException('网络请求发生错误，请稍后重试。');
    } on Object catch (e) {
      throw AppUpdateException('检查更新失败：$e');
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

bool _isUnsupportedDiskutil(io.ProcessResult result) {
  final details = _processDetails(result).toLowerCase();
  return details.contains('unknown command') ||
      details.contains('unknown verb') ||
      details.contains('unknown option') ||
      details.contains('unrecognized option') ||
      details.contains('invalid command') ||
      details.contains('did not recognize verb "image"') ||
      details.contains('usage: diskutil image');
}

String _processDetails(io.ProcessResult result) {
  final stdout = result.stdout.toString().trim();
  final stderr = result.stderr.toString().trim();
  return [stdout, stderr].where((value) => value.isNotEmpty).join('\n');
}

String? _mountPointFromOutput(String output) {
  for (final line in output.split('\n').reversed) {
    final match = RegExp(r'(/Volumes/[^\r\n]+)').firstMatch(line);
    if (match != null) return match.group(1)!.trim();
  }
  return null;
}

bool _isAllowedGitHubUri(Uri uri) =>
    uri.scheme == 'https' &&
    (uri.host == 'github.com' || uri.host.endsWith('.githubusercontent.com'));
