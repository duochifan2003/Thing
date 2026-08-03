import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as path;

const appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.19',
);
const appBuild = String.fromEnvironment('APP_BUILD', defaultValue: '42');
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
    final installerStarted = io.File(
      path.join(temporary.path, 'installer-started'),
    );
    await _download(asset.downloadUrl, archive, onProgress);

    if (operatingSystem == 'macos') {
      await _launchMacInstaller(temporary, archive, installerStarted);
    } else {
      await _launchWindowsInstaller(temporary, archive, installerStarted);
    }
    await _waitForInstallerStart(installerStarted);
    _exitApp(0);
  }

  Future<void> _waitForInstallerStart(io.File marker) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (await marker.exists()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw AppUpdateException(
      '更新安装器未启动，应用保持打开。请查看 ${path.dirname(marker.path)} 中的安装日志。',
    );
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
    io.File installerStarted,
  ) async {
    final executable = io.Platform.resolvedExecutable;
    final marker = '${path.separator}Contents${path.separator}MacOS';
    final markerIndex = executable.lastIndexOf(marker);
    if (markerIndex < 0) {
      throw const AppUpdateException('无法确定 macOS 应用安装位置。');
    }
    final targetApp = executable.substring(0, markerIndex);
    final script = io.File(path.join(temporary.path, 'install-update.sh'));
    final log = io.File(path.join(temporary.path, 'install-update.log'));
    await script.writeAsString('''#!/bin/zsh
set -u
PID=${io.pid}
ARCHIVE=${_shellQuote(archive.path)}
TARGET_APP=${_shellQuote(targetApp)}
LOG_PATH=${_shellQuote(log.path)}
START_MARKER=${_shellQuote(installerStarted.path)}
MOUNT_POINT="\${TMPDIR:-/tmp}/thing-update-mount-\$\$"
BACKUP_APP="\${TARGET_APP}.update-backup-\$\$"
exec >>"\$LOG_PATH" 2>&1
: >"\$START_MARKER"

log() {
  print -r -- "\$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ') \$*"
}

fail() {
  log "更新失败：\$1"
  /usr/bin/osascript -e 'display dialog "Thing 更新失败，请重试。" buttons {"好"} default button "好"' >/dev/null 2>&1 || true
  exit 1
}

cleanup() {
  /usr/bin/hdiutil detach "\$MOUNT_POINT" >/dev/null 2>&1 || true
  /bin/rm -rf "\$MOUNT_POINT"
}
trap cleanup EXIT

DEADLINE=\$(( \$(/bin/date +%s) + 60 ))
while /bin/kill -0 "\$PID" 2>/dev/null; do
  if [ "\$(/bin/date +%s)" -ge "\$DEADLINE" ]; then
    fail "等待应用退出超时"
  fi
  /bin/sleep 0.2
done
/bin/mkdir -p "\$MOUNT_POINT" || fail "无法创建临时目录"
/usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "\$MOUNT_POINT" "\$ARCHIVE" >/dev/null || fail "无法打开更新包"
SOURCE_APP="\$(/usr/bin/find "\$MOUNT_POINT" -maxdepth 1 -type d -name '*.app' -print -quit)"
[ -n "\$SOURCE_APP" ] || fail "更新包中没有找到应用"
log "准备安装 \$SOURCE_APP 到 \$TARGET_APP"

install_as_user() {
  /bin/mv "\$TARGET_APP" "\$BACKUP_APP" || return 1
  if /usr/bin/ditto "\$SOURCE_APP" "\$TARGET_APP"; then
    /bin/rm -rf "\$BACKUP_APP"
    return 0
  fi
  /bin/rm -rf "\$TARGET_APP"
  /bin/mv "\$BACKUP_APP" "\$TARGET_APP" || true
  return 1
}

install_as_admin() {
  /usr/bin/osascript - "\$SOURCE_APP" "\$TARGET_APP" "\$BACKUP_APP" <<'APPLESCRIPT'
on run argv
  set sourceApp to item 1 of argv
  set targetApp to item 2 of argv
  set backupApp to item 3 of argv
  set installCommand to "/bin/mv " & quoted form of targetApp & " " & quoted form of backupApp & " && if /usr/bin/ditto " & quoted form of sourceApp & " " & quoted form of targetApp & "; then /bin/rm -rf " & quoted form of backupApp & "; else /bin/rm -rf " & quoted form of targetApp & "; /bin/mv " & quoted form of backupApp & " " & quoted form of targetApp & "; exit 1; fi"
  do shell script installCommand with administrator privileges
end run
APPLESCRIPT
}

if ! install_as_user; then
  log "普通用户权限不足，申请管理员权限"
  install_as_admin || fail "没有权限替换应用"
fi
[ -d "\$TARGET_APP" ] || fail "应用替换后不存在"
/usr/bin/open "\$TARGET_APP" || fail "无法重新打开应用"
log "更新完成"
/usr/bin/hdiutil detach "\$MOUNT_POINT" >/dev/null 2>&1 || true
/bin/rm -rf "\$ARCHIVE" "\$LOG_PATH" "\$0" "\$BACKUP_APP"
''');
    final chmod = await io.Process.run('chmod', ['+x', script.path]);
    if (chmod.exitCode != 0) {
      throw const AppUpdateException('无法准备 macOS 更新安装器。');
    }
    try {
      await io.Process.start('/bin/zsh', [
        script.path,
      ], mode: io.ProcessStartMode.detached);
    } on io.ProcessException catch (error) {
      throw AppUpdateException('无法启动 macOS 更新安装器：${error.message}');
    }
  }

  Future<void> _launchWindowsInstaller(
    io.Directory temporary,
    io.File archive,
    io.File installerStarted,
  ) async {
    final executable = io.Platform.resolvedExecutable;
    final targetDirectory = path.dirname(executable);
    final executableName = path.basename(executable);
    final script = io.File(path.join(temporary.path, 'install-update.ps1'));
    final log = io.File(path.join(temporary.path, 'install-update.log'));
    await script.writeAsString('\uFEFF${_windowsUpdateScript()}');
    await io.Process.start('powershell.exe', [
      '-NoProfile',
      '-WindowStyle',
      'Hidden',
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
      '-LogPath',
      log.path,
      '-StartMarker',
      installerStarted.path,
    ], mode: io.ProcessStartMode.detached);
  }
}

String _shellQuote(String value) {
  final escaped = value.replaceAll("'", "'\"'\"'");
  return "'$escaped'";
}

String _windowsUpdateScript() => r'''
param(
  [int]$ProcessId,
  [string]$Archive,
  [string]$TargetDirectory,
  [string]$ExecutableName,
  [string]$LogPath,
  [string]$StartMarker,
  [switch]$Elevated
)
$ErrorActionPreference = 'Stop'
$UpdateDirectory = Split-Path -Parent $Archive

function Write-UpdateLog([string]$Message) {
  try {
    Add-Content -LiteralPath $LogPath -Value ((Get-Date).ToString('o') + ' ' + $Message)
  } catch {
  }
}

function Show-UpdateFailure([string]$Message) {
  try {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
      $Message,
      'Thing',
      [System.Windows.MessageBoxButton]::OK,
      [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
  } catch {
  }
}

function Test-TargetDirectoryWritable {
  $probe = Join-Path $TargetDirectory ('.thing-update-probe-' + [Guid]::NewGuid().ToString('N'))
  try {
    New-Item -Path $probe -ItemType File -Force | Out-Null
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    return $true
  } catch {
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    return $false
  }
}

function Start-ElevatedUpdate {
  function Quote-ProcessArgument([string]$Value) {
    return '"' + $Value + '"'
  }
  $argumentList = @(
    '-NoProfile',
    '-WindowStyle', 'Hidden',
    '-ExecutionPolicy', 'Bypass',
    '-File', (Quote-ProcessArgument $PSCommandPath),
    '-ProcessId', [string]$ProcessId,
    '-Archive', (Quote-ProcessArgument $Archive),
    '-TargetDirectory', (Quote-ProcessArgument $TargetDirectory),
    '-ExecutableName', (Quote-ProcessArgument $ExecutableName),
    '-LogPath', (Quote-ProcessArgument $LogPath),
    '-StartMarker', (Quote-ProcessArgument $StartMarker),
    '-Elevated'
  ) -join ' '
  $child = Start-Process `
    -FilePath 'powershell.exe' `
    -WindowStyle Hidden `
    -Verb RunAs `
    -ArgumentList $argumentList `
    -PassThru
  if ($null -eq $child) { throw '无法启动管理员权限更新进程。' }
  Write-UpdateLog '已请求管理员权限重试更新。'
}

function Invoke-Update {
  Set-Location ([IO.Path]::GetTempPath())
  $processDeadline = (Get-Date).AddSeconds(60)
  while (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
    if ((Get-Date) -gt $processDeadline) { throw '等待旧程序退出超时。' }
    Start-Sleep -Milliseconds 200
  }

  $extractDirectory = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ('thing-update-extract-' + [Guid]::NewGuid().ToString('N'))
  $stagedDirectory = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ('thing-update-stage-' + [Guid]::NewGuid().ToString('N'))
  $backupDirectory = "${TargetDirectory}.update-backup-" + [Guid]::NewGuid().ToString('N')
  try {
    New-Item -Path $extractDirectory -ItemType Directory -Force | Out-Null
    Expand-Archive -LiteralPath $Archive -DestinationPath $extractDirectory -Force
    $sourceExecutable = Get-ChildItem -LiteralPath $extractDirectory `
      -Filter $ExecutableName -File -Recurse | Select-Object -First 1
    if ($null -eq $sourceExecutable) { throw '更新包中没有找到应用程序。' }

    $targetExecutable = Join-Path $TargetDirectory $ExecutableName
    $fileDeadline = (Get-Date).AddSeconds(30)
    while (Test-Path -LiteralPath $targetExecutable) {
      try {
        $stream = [IO.File]::Open(
          $targetExecutable,
          [IO.FileMode]::Open,
          [IO.FileAccess]::ReadWrite,
          [IO.FileShare]::None
        )
        $stream.Dispose()
        break
      } catch {
        if ((Get-Date) -gt $fileDeadline) { throw '旧程序文件仍被占用。' }
        Start-Sleep -Milliseconds 200
      }
    }

    New-Item -Path $stagedDirectory -ItemType Directory -Force | Out-Null
    Get-ChildItem -LiteralPath $sourceExecutable.Directory.FullName -Force |
      Copy-Item -Destination $stagedDirectory -Recurse -Force
    $stagedExecutable = Join-Path $stagedDirectory $ExecutableName
    if (-not (Test-Path -LiteralPath $stagedExecutable)) {
      throw '更新文件准备后未找到应用程序。'
    }

    $swapDeadline = (Get-Date).AddSeconds(30)
    while ($true) {
      $movedTarget = $false
      try {
        Move-Item -LiteralPath $TargetDirectory -Destination $backupDirectory
        $movedTarget = $true
        New-Item -Path $TargetDirectory -ItemType Directory -Force | Out-Null
        Get-ChildItem -LiteralPath $stagedDirectory -Force |
          Copy-Item -Destination $TargetDirectory -Recurse -Force
        if (-not (Test-Path -LiteralPath $targetExecutable)) {
          throw '替换文件后未找到应用程序。'
        }
        Remove-Item -LiteralPath $backupDirectory -Recurse -Force
        $movedTarget = $false
        break
      } catch {
        if ($movedTarget) {
          Remove-Item -LiteralPath $TargetDirectory -Recurse -Force -ErrorAction SilentlyContinue
          if (Test-Path -LiteralPath $backupDirectory) {
            Move-Item -LiteralPath $backupDirectory -Destination $TargetDirectory
          }
        }
        if ((Get-Date) -gt $swapDeadline) {
          throw '替换旧应用目录超时。'
        }
        Start-Sleep -Milliseconds 200
      }
    }
    Start-Process -FilePath $targetExecutable -WorkingDirectory $TargetDirectory
    Write-UpdateLog '更新完成。'
  } finally {
    Remove-Item -LiteralPath $extractDirectory -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stagedDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}

try {
  New-Item -Path $StartMarker -ItemType File -Force | Out-Null
  Write-UpdateLog '安装器已启动。'
  if (-not $Elevated -and -not (Test-TargetDirectoryWritable)) {
    Write-UpdateLog '安装目录需要管理员权限，准备请求 UAC。'
    Start-ElevatedUpdate
    exit 0
  }
  if (-not $Elevated) {
    try {
      Invoke-Update
    } catch {
      $accessDenied = $_.Exception -is [UnauthorizedAccessException] `
        -or $_.FullyQualifiedErrorId -like '*UnauthorizedAccess*'
      if (-not $accessDenied) { throw }
      Start-ElevatedUpdate
      exit 0
    }
  } else {
    Invoke-Update
  }
  Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $LogPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $StartMarker -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $UpdateDirectory -Recurse -Force -ErrorAction SilentlyContinue
} catch {
  $message = 'Thing 更新失败，请重试。' + [Environment]::NewLine + $_.Exception.Message
  Write-UpdateLog $message
  Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $StartMarker -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
  Show-UpdateFailure $message
  exit 1
}
''';

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
