import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'app_settings.dart';
import 'archive_repository.dart';
import 'sync_models.dart';

class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SyncService {
  SyncService(this.repository);

  static const fileName = 'person-event-atlas.sync.json';

  final ArchiveRepository repository;
  StreamSubscription<FileSystemEvent>? _watchSubscription;
  Timer? _watchDebounce;
  DateTime? _ignoreEventsUntil;
  bool _running = false;

  Future<void> watch(
    String directory,
    Future<void> Function() onChanged,
  ) async {
    await stopWatching();
    final folder = Directory(directory);
    await folder.create(recursive: true);
    _watchSubscription = folder.watch().listen((event) {
      if (path.basename(event.path) != fileName) return;
      final ignoreUntil = _ignoreEventsUntil;
      if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) return;
      _ignoreEventsUntil = null;
      _watchDebounce?.cancel();
      _watchDebounce = Timer(const Duration(milliseconds: 350), () {
        unawaited(onChanged());
      });
    });
  }

  Future<void> stopWatching() async {
    _watchDebounce?.cancel();
    _watchDebounce = null;
    await _watchSubscription?.cancel();
    _watchSubscription = null;
  }

  Future<SyncReport> synchronize({
    required String directory,
    required TrashRetention retention,
    Map<String, SyncConflictChoice> resolutions = const {},
    bool confirmInitialMerge = false,
  }) async {
    if (_running) {
      final metadata = await repository.loadSyncMetadata();
      return SyncReport(
        outcome: SyncOutcome.synchronized,
        metadata: metadata,
        message: '同步正在进行中。',
      );
    }
    _running = true;
    try {
      return await _synchronize(
        directory: directory,
        retention: retention,
        resolutions: resolutions,
        confirmInitialMerge: confirmInitialMerge,
      );
    } finally {
      _running = false;
    }
  }

  Future<SyncReport> _synchronize({
    required String directory,
    required TrashRetention retention,
    required Map<String, SyncConflictChoice> resolutions,
    required bool confirmInitialMerge,
  }) async {
    final folder = Directory(directory);
    try {
      await folder.create(recursive: true);
      await repository.purgeExpiredTrash(retention);
      final deviceId = await repository.loadDeviceId();
      final localArchive = await repository.load();
      final localTrash = await repository.loadTrash();
      final localTombstones = await repository.loadTombstones();
      final local = SyncEnvelope(
        archive: localArchive,
        trash: localTrash,
        tombstones: localTombstones,
        retentionDays: retention.days,
        writtenAt: DateTime.now().toUtc(),
        deviceId: deviceId,
      );
      final file = File(path.join(directory, fileName));
      SyncEnvelope? remote;
      try {
        remote = await _readRemote(file);
      } on FormatException catch (error) {
        return _failed('同步文件无法读取：${error.message}');
      } on FileSystemException catch (error) {
        return _failed('同步文件无法读取：${error.message}');
      } catch (_) {
        return _failed('同步文件无法读取。');
      }

      final previous = await repository.loadSyncMetadata();
      if (remote == null) {
        await _writeAtomic(file, local.encode(), deviceId);
        final metadata = _success(baseline: local, status: '已上传');
        await repository.saveSyncMetadata(metadata);
        return SyncReport(
          outcome: SyncOutcome.uploaded,
          metadata: metadata,
          retentionDays: local.retentionDays,
        );
      }

      final result = SyncMerger.merge(
        local: local,
        remote: remote,
        baseline: previous.baseline,
        resolutions: resolutions,
      );
      if (previous.baseline == null &&
          _hasContent(local) &&
          _hasContent(remote) &&
          !confirmInitialMerge) {
        final metadata = SyncMetadata(
          status: '待确认首次合并',
          conflicts: result.conflicts,
        );
        await repository.saveSyncMetadata(metadata);
        return SyncReport(
          outcome: SyncOutcome.preview,
          metadata: metadata,
          retentionDays: remote.retentionDays,
          message:
              '本机有 ${local.archive.people.length + local.archive.events.length} 条记录，'
              '同步文件有 ${remote.archive.people.length + remote.archive.events.length} 条记录，'
              '将合并为一份档案。当前发现 ${result.conflicts.length} 条同 ID 冲突。',
        );
      }
      if (result.conflicts.isNotEmpty &&
          result.conflicts.any(
            (conflict) => !resolutions.containsKey(conflict.key),
          )) {
        final metadata = SyncMetadata(
          baseline: previous.baseline,
          lastSyncAt: previous.lastSyncAt,
          status: '存在冲突',
          conflicts: result.conflicts,
        );
        await repository.saveSyncMetadata(metadata);
        return SyncReport(
          outcome: SyncOutcome.conflicts,
          metadata: metadata,
          retentionDays: remote.retentionDays,
          message: '有 ${result.conflicts.length} 条记录需要选择保留版本。',
        );
      }

      final resultMatchesLocal = _sameContent(result.envelope, local);
      if (_sameContent(result.envelope, remote)) {
        if (!resultMatchesLocal) {
          await repository.replaceSyncSnapshot(
            result.envelope.archive,
            result.envelope.trash,
            result.envelope.tombstones,
          );
        }
        final downloaded = !_hasContent(local) && _hasContent(remote);
        final metadata = _success(
          baseline: remote,
          status: downloaded ? '已下载' : '已同步',
        );
        await repository.saveSyncMetadata(metadata);
        return SyncReport(
          outcome: downloaded
              ? SyncOutcome.downloaded
              : SyncOutcome.synchronized,
          metadata: metadata,
          retentionDays: remote.retentionDays,
        );
      }

      final merged = SyncEnvelope(
        archive: result.envelope.archive,
        trash: result.envelope.trash,
        tombstones: result.envelope.tombstones,
        retentionDays: result.envelope.retentionDays,
        writtenAt: DateTime.now().toUtc(),
        deviceId: deviceId,
      );
      await repository.replaceSyncSnapshot(
        merged.archive,
        merged.trash,
        merged.tombstones,
      );
      try {
        await _writeAtomic(file, merged.encode(), deviceId);
      } on FileSystemException catch (error) {
        return _failed('同步文件无法写入：${error.message}');
      } catch (_) {
        return _failed('同步文件无法写入。');
      }
      final localHadContent = _hasContent(local);
      final remoteHadContent = _hasContent(remote);
      final outcome = !localHadContent && remoteHadContent
          ? SyncOutcome.downloaded
          : SyncOutcome.synchronized;
      final metadata = _success(
        baseline: merged,
        status: outcome == SyncOutcome.downloaded ? '已下载' : '已同步',
      );
      await repository.saveSyncMetadata(metadata);
      return SyncReport(
        outcome: outcome,
        metadata: metadata,
        retentionDays: merged.retentionDays,
      );
    } on FormatException catch (error) {
      return _failed('本地数据无法合并：${error.message}');
    } on FileSystemException catch (error) {
      return _failed('同步目录不可用：${error.message}');
    } catch (_) {
      return _failed('同步失败，本机资料保持不变。');
    }
  }

  Future<void> _writeAtomic(
    File target,
    String contents,
    String deviceId,
  ) async {
    final temporary = File('${target.path}.$deviceId.tmp');
    await temporary.writeAsString(contents, flush: true);
    _ignoreEventsUntil = DateTime.now().add(const Duration(seconds: 1));
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      await temporary.copy(target.path);
      await temporary.delete();
    }
  }

  Future<SyncEnvelope?> _readRemote(File file) async {
    const retryDelays = [
      Duration.zero,
      Duration(milliseconds: 200),
      Duration(milliseconds: 500),
      Duration(seconds: 1),
    ];
    Object? lastError;
    for (var attempt = 0; attempt < retryDelays.length; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(retryDelays[attempt]);
      }
      try {
        if (!await file.exists()) continue;
        return SyncEnvelope.decode(await file.readAsString());
      } on FormatException catch (error) {
        lastError = error;
      } on FileSystemException catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) throw lastError;
    return null;
  }

  Future<SyncReport> _failed(String message) async {
    final previous = await repository.loadSyncMetadata();
    final metadata = SyncMetadata(
      baseline: previous.baseline,
      lastSyncAt: previous.lastSyncAt,
      status: '同步失败',
      error: message,
      conflicts: previous.conflicts,
    );
    try {
      await repository.saveSyncMetadata(metadata);
    } catch (_) {
      // Keep the original sync error when the local status cannot be stored.
    }
    return SyncReport(
      outcome: SyncOutcome.failed,
      metadata: metadata,
      message: message,
    );
  }

  SyncMetadata _success({
    required SyncEnvelope baseline,
    required String status,
  }) => SyncMetadata(
    baseline: baseline,
    lastSyncAt: DateTime.now().toUtc(),
    status: status,
  );

  bool _hasContent(SyncEnvelope envelope) =>
      envelope.archive.people.isNotEmpty ||
      envelope.archive.events.isNotEmpty ||
      envelope.archive.revisions.isNotEmpty ||
      envelope.archive.allTagCatalog.isNotEmpty ||
      envelope.trash.isNotEmpty ||
      envelope.tombstones.isNotEmpty;

  bool _sameContent(SyncEnvelope left, SyncEnvelope right) {
    final leftJson = left.toJson()
      ..remove('writtenAt')
      ..remove('deviceId');
    final rightJson = right.toJson()
      ..remove('writtenAt')
      ..remove('deviceId');
    return jsonEncode(leftJson) == jsonEncode(rightJson);
  }

  Future<void> dispose() => stopWatching();
}
