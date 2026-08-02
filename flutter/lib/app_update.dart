import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as path;

const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.6');
const appBuild = String.fromEnvironment('APP_BUILD', defaultValue: '29');
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
  const AppUpdateAsset({required this.name, required this.downloadUrl});

  final String name;
  final Uri downloadUrl;
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
        'windows' => name.contains('windows') && name.endsWith('.zip'),
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
    return candidates.first;
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
        assets.add(AppUpdateAsset(name: name, downloadUrl: uri));
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

    final temporary = await io.Directory.systemTemp.createTemp('thing-update-');
    final archive = io.File(
      path.join(temporary.path, _safeFileName(asset.name)),
    );
    await _download(asset.downloadUrl, archive, onProgress);

    if (operatingSystem == 'macos') {
      await _launchMacInstaller(temporary, archive);
    } else {
      await _launchWindowsInstaller(temporary, archive);
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

  Future<void> _download(
    Uri uri,
    io.File destination,
    UpdateProgress? onProgress,
  ) async {
    final client = io.HttpClient()..userAgent = 'Thing/$currentVersion';
    io.IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != io.HttpStatus.ok) {
        throw AppUpdateException('更新包下载失败（HTTP ${response.statusCode}）。');
      }
      final total = response.contentLength;
      var received = 0;
      sink = destination.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      onProgress?.call(1);
    } on AppUpdateException {
      rethrow;
    } on io.SocketException {
      throw const AppUpdateException('更新包下载失败，请检查网络后重试。');
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  Future<void> _launchMacInstaller(
    io.Directory temporary,
    io.File archive,
  ) async {
    final executable = io.Platform.resolvedExecutable;
    final marker = '${path.separator}Contents${path.separator}MacOS';
    final markerIndex = executable.lastIndexOf(marker);
    if (markerIndex < 0) {
      throw const AppUpdateException('无法确定 macOS 应用安装位置。');
    }
    final targetApp = executable.substring(0, markerIndex);
    final script = io.File(path.join(temporary.path, 'install-update.sh'));
    await script.writeAsString('''#!/bin/sh
set -eu
PID="\$1"
ARCHIVE="\$2"
TARGET_APP="\$3"
MOUNT_POINT="\${TMPDIR:-/tmp}/event-atlas-mount-\$\$"
while kill -0 "\$PID" 2>/dev/null; do sleep 1; done
mkdir -p "\$MOUNT_POINT"
cleanup() {
  hdiutil detach "\$MOUNT_POINT" >/dev/null 2>&1 || true
  rm -rf "\$MOUNT_POINT" "\$ARCHIVE" "\$0"
}
trap cleanup EXIT
hdiutil attach -nobrowse -readonly -mountpoint "\$MOUNT_POINT" "\$ARCHIVE" >/dev/null
SOURCE_APP="\$(find "\$MOUNT_POINT" -maxdepth 1 -name '*.app' -print -quit)"
if [ -z "\$SOURCE_APP" ]; then exit 1; fi
rm -rf "\$TARGET_APP"
ditto "\$SOURCE_APP" "\$TARGET_APP"
open "\$TARGET_APP"
''');
    await io.Process.run('chmod', ['+x', script.path]);
    await io.Process.start('/bin/sh', [
      script.path,
      '${io.pid}',
      archive.path,
      targetApp,
    ], mode: io.ProcessStartMode.detached);
  }

  Future<void> _launchWindowsInstaller(
    io.Directory temporary,
    io.File archive,
  ) async {
    final executable = io.Platform.resolvedExecutable;
    final targetDirectory = path.dirname(executable);
    final executableName = path.basename(executable);
    final script = io.File(path.join(temporary.path, 'install-update.ps1'));
    await script.writeAsString(r'''
param(
  [int]$ProcessId,
  [string]$Archive,
  [string]$TargetDirectory,
  [string]$ExecutableName
)
$ErrorActionPreference = "Stop"
while (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
  Start-Sleep -Milliseconds 500
}
$ExtractDirectory = Join-Path $env:TEMP ("event-atlas-update-" + $ProcessId)
Remove-Item $ExtractDirectory -Recurse -Force -ErrorAction SilentlyContinue
New-Item $ExtractDirectory -ItemType Directory -Force | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $ExtractDirectory -Force
$SourceExecutable = Get-ChildItem $ExtractDirectory -Filter "*.exe" -File -Recurse |
  Sort-Object @{ Expression = { $_.Name -ne $ExecutableName } }, FullName |
  Select-Object -First 1
if ($null -eq $SourceExecutable) { throw "更新包中没有找到应用程序。" }
$InstalledExecutableName = $SourceExecutable.Name
Copy-Item (Join-Path $SourceExecutable.Directory.FullName "*") $TargetDirectory -Recurse -Force
if ($ExecutableName -ne $InstalledExecutableName) {
  Remove-Item (Join-Path $TargetDirectory $ExecutableName) -Force -ErrorAction SilentlyContinue
}
Remove-Item $Archive -Force -ErrorAction SilentlyContinue
Remove-Item $ExtractDirectory -Recurse -Force -ErrorAction SilentlyContinue
Start-Process (Join-Path $TargetDirectory $InstalledExecutableName)
Remove-Item $PSCommandPath -Force -ErrorAction SilentlyContinue
''');
    await io.Process.start('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script.path,
      '-ProcessId',
      '${io.pid}',
      '-Archive',
      archive.path,
      '-TargetDirectory',
      targetDirectory,
      '-ExecutableName',
      executableName,
    ], mode: io.ProcessStartMode.detached);
  }
}

String _safeFileName(String value) {
  final name = path.basename(value).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return name.isEmpty ? 'event-atlas-update.bin' : name;
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
  final normalized = _normalizeVersion(value);
  final parts = normalized.split('.').map(int.parse).toList();
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
