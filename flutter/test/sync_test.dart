import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:person_event_atlas/app_settings.dart';
import 'package:person_event_atlas/archive.dart';
import 'package:person_event_atlas/archive_repository.dart';
import 'package:person_event_atlas/sync_models.dart';
import 'package:person_event_atlas/sync_service.dart';

void main() {
  test('round-trips the sync envelope and rejects unsupported formats', () {
    final envelope = SyncEnvelope(
      archive: Archive(people: [_person('p-1')], events: const []),
      trash: [
        TrashEntry(
          id: 'p-2',
          entityType: EntityType.person,
          deletedAt: DateTime.utc(2025, 1, 2),
          person: _person('p-2'),
        ),
      ],
      tombstones: [
        SyncTombstone(
          id: 'p-2',
          entityType: EntityType.person,
          deletedAt: DateTime.utc(2025, 1, 2),
        ),
      ],
      retentionDays: 30,
      writtenAt: DateTime.utc(2025, 1, 3),
      deviceId: 'device-a',
    );

    final decoded = SyncEnvelope.decode(envelope.encode());
    expect(decoded.archive.people.single.id, 'p-1');
    expect(decoded.trash.single.title, '林岚');
    expect(decoded.tombstones.single.id, 'p-2');
    expect(decoded.retentionDays, 30);
    expect(
      () => SyncEnvelope.decode(
        jsonEncode({...envelope.toJson(), 'version': 99}),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('merges one-sided changes and exposes simultaneous edits', () {
    final base = _envelope(_person('p-1'), 'base', DateTime.utc(2025, 1, 1));
    final local = SyncEnvelope(
      archive: base.archive.copyWith(
        people: [base.archive.people.single.copyWith(name: '本机人物')],
      ),
      trash: const [],
      tombstones: const [],
      retentionDays: 30,
      writtenAt: DateTime.utc(2025, 1, 2),
      deviceId: 'local',
    );
    final remote = SyncEnvelope(
      archive: base.archive.copyWith(
        people: [base.archive.people.single.copyWith(name: '远端人物')],
      ),
      trash: const [],
      tombstones: const [],
      retentionDays: 30,
      writtenAt: DateTime.utc(2025, 1, 3),
      deviceId: 'remote',
    );

    final conflict = SyncMerger.merge(
      local: local,
      remote: remote,
      baseline: base,
    );
    expect(conflict.conflicts.single.key, 'person:p-1');

    final resolved = SyncMerger.merge(
      local: local,
      remote: remote,
      baseline: base,
      resolutions: const {'person:p-1': SyncConflictChoice.remote},
    );
    expect(resolved.conflicts, isNotEmpty);
    expect(resolved.envelope.archive.people.single.name, '远端人物');
  });

  test('keeps deletion tombstones when the other side is unchanged', () {
    final base = _envelope(_person('p-1'), 'base', DateTime.utc(2025, 1, 1));
    final local = SyncEnvelope(
      archive: const Archive(people: [], events: []),
      trash: const [],
      tombstones: [
        SyncTombstone(
          id: 'p-1',
          entityType: EntityType.person,
          deletedAt: DateTime.utc(2025, 1, 2),
        ),
      ],
      retentionDays: 30,
      writtenAt: DateTime.utc(2025, 1, 2),
      deviceId: 'local',
    );
    final result = SyncMerger.merge(local: local, remote: base, baseline: base);
    expect(result.conflicts, isEmpty);
    expect(result.envelope.archive.people, isEmpty);
    expect(result.envelope.tombstones.single.id, 'p-1');
  });

  test('previews a first two-sided sync before applying it', () async {
    final root = await Directory.systemTemp.createTemp('event-atlas-preview-');
    addTearDown(() => root.delete(recursive: true));
    final syncDirectory = Directory(path.join(root.path, 'shared'));
    await syncDirectory.create(recursive: true);
    final remoteEnvelope = _envelope(
      _person('p-2'),
      'remote',
      DateTime.utc(2025, 1, 2),
    );
    await File(
      path.join(syncDirectory.path, SyncService.fileName),
    ).writeAsString(remoteEnvelope.encode());
    final repository = ArchiveRepository(
      databasePath: path.join(root.path, 'archive.sqlite'),
    );
    addTearDown(repository.close);
    await repository.replace(
      Archive(people: [_person('p-1')], events: const []),
    );
    final service = SyncService(repository);

    final preview = await service.synchronize(
      directory: syncDirectory.path,
      retention: TrashRetention.thirtyDays,
    );
    expect(preview.outcome, SyncOutcome.preview);
    expect((await repository.load()).people.single.id, 'p-1');

    final applied = await service.synchronize(
      directory: syncDirectory.path,
      retention: TrashRetention.thirtyDays,
      confirmInitialMerge: true,
    );
    expect(applied.outcome, SyncOutcome.synchronized);
    expect((await repository.load()).people.map((person) => person.id), {
      'p-1',
      'p-2',
    });
  });

  test(
    'uploads, downloads, and preserves local data on a damaged file',
    () async {
      final root = await Directory.systemTemp.createTemp('event-atlas-sync-');
      addTearDown(() => root.delete(recursive: true));
      final syncDirectory = path.join(root.path, 'shared');
      final firstPath = path.join(root.path, 'first.sqlite');
      final first = ArchiveRepository(databasePath: firstPath);
      await first.replace(Archive(people: [_person('p-1')], events: const []));
      final firstService = SyncService(first);
      final uploaded = await firstService.synchronize(
        directory: syncDirectory,
        retention: TrashRetention.thirtyDays,
      );
      expect(uploaded.outcome, SyncOutcome.uploaded);
      expect(
        await File(path.join(syncDirectory, SyncService.fileName)).exists(),
        isTrue,
      );
      await first.close();

      final secondPath = path.join(root.path, 'second.sqlite');
      final second = ArchiveRepository(databasePath: secondPath);
      final downloaded = await SyncService(second).synchronize(
        directory: syncDirectory,
        retention: TrashRetention.thirtyDays,
      );
      expect(downloaded.outcome, SyncOutcome.downloaded);
      expect((await second.load()).people.single.id, 'p-1');

      await File(
        path.join(syncDirectory, SyncService.fileName),
      ).writeAsString('{bad');
      final failed = await SyncService(second).synchronize(
        directory: syncDirectory,
        retention: TrashRetention.thirtyDays,
      );
      expect(failed.outcome, SyncOutcome.failed);
      expect((await second.load()).people.single.id, 'p-1');
      await second.close();
    },
  );

  test('applies a remote deletion to an existing local archive', () async {
    final root = await Directory.systemTemp.createTemp(
      'event-atlas-delete-sync-',
    );
    addTearDown(() => root.delete(recursive: true));
    final syncDirectory = path.join(root.path, 'shared');
    final first = ArchiveRepository(
      databasePath: path.join(root.path, 'first.sqlite'),
    );
    final second = ArchiveRepository(
      databasePath: path.join(root.path, 'second.sqlite'),
    );
    addTearDown(first.close);
    addTearDown(second.close);

    await first.replace(Archive(people: [_person('p-1')], events: const []));
    final firstService = SyncService(first);
    final secondService = SyncService(second);
    await firstService.synchronize(
      directory: syncDirectory,
      retention: TrashRetention.thirtyDays,
    );
    await secondService.synchronize(
      directory: syncDirectory,
      retention: TrashRetention.thirtyDays,
    );

    expect(await first.deletePerson('p-1'), isTrue);
    await firstService.synchronize(
      directory: syncDirectory,
      retention: TrashRetention.thirtyDays,
    );
    await secondService.synchronize(
      directory: syncDirectory,
      retention: TrashRetention.thirtyDays,
    );

    expect((await second.load()).people, isEmpty);
    expect((await second.loadTrash()).single.id, 'p-1');
    expect((await second.loadTombstones()).single.id, 'p-1');
  });

  test(
    'moves deleted records to trash, restores them, and keeps tombstones after purge',
    () async {
      final root = await Directory.systemTemp.createTemp('event-atlas-trash-');
      addTearDown(() => root.delete(recursive: true));
      final repository = ArchiveRepository(
        databasePath: path.join(root.path, 'archive.sqlite'),
      );
      addTearDown(repository.close);
      await repository.replace(
        Archive(people: [_person('p-1')], events: const []),
      );

      expect(await repository.deletePerson('p-1'), isTrue);
      expect((await repository.load()).people, isEmpty);
      expect((await repository.loadTrash()).single.id, 'p-1');
      await repository.restoreTrash((await repository.loadTrash()).single);
      expect((await repository.load()).people.single.id, 'p-1');
      expect(await repository.loadTrash(), isEmpty);

      await repository.deletePerson('p-1');
      await repository.purgeExpiredTrash(
        TrashRetention.sevenDays,
        now: DateTime.now().toUtc().add(const Duration(days: 8)),
      );
      expect(await repository.loadTrash(), isEmpty);
      expect((await repository.loadTombstones()).single.id, 'p-1');
    },
  );
}

SyncEnvelope _envelope(Person person, String deviceId, DateTime writtenAt) =>
    SyncEnvelope(
      archive: Archive(people: [person], events: const []),
      trash: const [],
      tombstones: const [],
      retentionDays: 30,
      writtenAt: writtenAt,
      deviceId: deviceId,
    );

Person _person(String id) => Person(
  id: id,
  name: '林岚',
  bio: '',
  tags: const [],
  notes: '',
  sources: const [],
  createdAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
);
