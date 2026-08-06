import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'app_settings.dart';
import 'archive.dart';
import 'sync_models.dart';

class ImportPreview {
  const ImportPreview({
    required this.add,
    required this.duplicate,
    required this.conflict,
  });

  final int add;
  final int duplicate;
  final int conflict;
}

class ArchiveRepository {
  ArchiveRepository({this.databasePath});

  final String? databasePath;
  Database? _database;
  Future<void> _writes = Future.value();

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) return existing;

    if (databasePath == null) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }
    final databaseFile =
        databasePath ??
        path.join(
          (await getApplicationSupportDirectory()).path,
          'person-event-atlas.sqlite',
        );
    if (databaseFile != ':memory:') {
      await Directory(path.dirname(databaseFile)).create(recursive: true);
    }
    final database = sqlite3.open(databaseFile);
    database.execute('PRAGMA foreign_keys = ON');
    database.execute('PRAGMA journal_mode = WAL');
    database.execute('PRAGMA busy_timeout = 1000');
    final version = _schemaVersion(database);
    if (!_tableExists(database, 'events')) {
      _createSchema(database);
      database.execute('PRAGMA user_version = 3');
    } else if (version < 3) {
      _transaction(database, () {
        final columns = database
            .select('PRAGMA table_info(events)')
            .map((row) => row['name'] as String)
            .toSet();
        if (!columns.contains('status')) {
          database.execute(
            "ALTER TABLE events ADD COLUMN status TEXT NOT NULL DEFAULT 'completed'",
          );
        }
        if (!columns.contains('images')) {
          database.execute(
            "ALTER TABLE events ADD COLUMN images TEXT NOT NULL DEFAULT '[]'",
          );
        }
        _createRelationsTable(database);
        database.execute('PRAGMA user_version = 3');
      });
    } else {
      _createRelationsTable(database);
    }
    _database = database;
    return database;
  }

  Future<Archive> load() async {
    final database = await _open();
    final people = database
        .select('SELECT * FROM people ORDER BY name COLLATE NOCASE')
        .map(_personFromRow)
        .toList();
    final events = database
        .select('SELECT * FROM events ORDER BY start DESC')
        .map((row) => _eventFromRow(database, row))
        .toList();
    final revisions = database
        .select('SELECT * FROM revisions ORDER BY at ASC')
        .map(_revisionFromRow)
        .toList();
    final legacyTags = _metadataTags(database, 'custom_tags');
    final personTags = _metadataTags(
      database,
      'person_tags',
      fallback: legacyTags,
    );
    final eventTags = _metadataTags(
      database,
      'event_tags',
      fallback: legacyTags,
    );
    return Archive(
      people: people,
      events: events,
      customTags: {...legacyTags, ...personTags, ...eventTags}.toList()..sort(),
      personTags: personTags,
      eventTags: eventTags,
      revisions: revisions,
    );
  }

  Future<AppSettings> loadSettings() async {
    final database = await _open();
    final rows = database.select(
      "SELECT value FROM metadata WHERE key = 'app_settings'",
    );
    if (rows.isEmpty) return AppSettings.defaults;
    try {
      return AppSettings.fromJson(jsonDecode(rows.single['value'] as String));
    } catch (_) {
      return AppSettings.defaults;
    }
  }

  Future<void> saveSettings(AppSettings settings) => _serialize(() async {
    final database = await _open();
    _transaction(
      database,
      () => database.execute(
        "INSERT INTO metadata (key, value) VALUES ('app_settings', ?) "
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        [settings.encode()],
      ),
    );
  });

  Future<String> loadDeviceId() => _serialize(() async {
    final database = await _open();
    final rows = database.select(
      "SELECT value FROM metadata WHERE key = 'device_id'",
    );
    if (rows.isNotEmpty && (rows.single['value'] as String).isNotEmpty) {
      return rows.single['value'] as String;
    }
    final id =
        'device-${DateTime.now().toUtc().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    _transaction(
      database,
      () => database.execute(
        "INSERT INTO metadata (key, value) VALUES ('device_id', ?)",
        [id],
      ),
    );
    return id;
  });

  Future<List<TrashEntry>> loadTrash() async {
    final database = await _open();
    return _readTrash(database);
  }

  Future<List<SyncTombstone>> loadTombstones() async {
    final database = await _open();
    return _readTombstones(database);
  }

  Future<SyncMetadata> loadSyncMetadata() async {
    final database = await _open();
    final rows = database.select(
      "SELECT value FROM metadata WHERE key = 'sync_metadata'",
    );
    if (rows.isEmpty) return const SyncMetadata();
    try {
      final value = jsonDecode(rows.single['value'] as String);
      if (value is! Map) return const SyncMetadata();
      return SyncMetadata.fromJson(Map<String, dynamic>.from(value));
    } catch (_) {
      return const SyncMetadata(status: '同步状态已重置');
    }
  }

  Future<void> saveSyncMetadata(SyncMetadata metadata) => _serialize(() async {
    final database = await _open();
    _transaction(
      database,
      () => database.execute(
        "INSERT INTO metadata (key, value) VALUES ('sync_metadata', ?) "
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [jsonEncode(metadata.toJson())],
      ),
    );
  });

  Future<void> replaceSyncSnapshot(
    Archive archive,
    List<TrashEntry> trash,
    List<SyncTombstone> tombstones,
  ) => _serialize(() async {
    _validateArchive(archive);
    final database = await _open();
    _transaction(database, () {
      _replaceArchive(database, archive);
      _writeTrash(database, trash);
      _writeTombstones(database, tombstones);
    });
  });

  Future<int> purgeExpiredTrash(TrashRetention retention, {DateTime? now}) =>
      _serialize(() async {
        final database = await _open();
        final cutoff = (now ?? DateTime.now()).toUtc();
        final entries = _readTrash(database);
        final expired = entries
            .where(
              (entry) =>
                  retention.days == 0 ||
                  !entry.deletedAt
                      .toUtc()
                      .add(Duration(days: retention.days))
                      .isAfter(cutoff),
            )
            .toList();
        if (expired.isEmpty) return 0;
        _transaction(database, () {
          for (final entry in expired) {
            database.execute(
              'DELETE FROM revisions WHERE entity_type = ? AND entity_id = ?',
              [entry.entityType.name, entry.id],
            );
            if (entry.entityType == EntityType.person) {
              database.execute('DELETE FROM people WHERE id = ?', [entry.id]);
            } else {
              database.execute('DELETE FROM events WHERE id = ?', [entry.id]);
            }
          }
          _writeTrash(
            database,
            entries.where((entry) => !expired.contains(entry)).toList(),
          );
        });
        return expired.length;
      });

  Future<void> purgeTrashEntry(TrashEntry entry) => _serialize(() async {
    final database = await _open();
    _transaction(database, () {
      final stored = _readTrash(database).any(
        (item) => item.entityType == entry.entityType && item.id == entry.id,
      );
      if (!stored) throw const FormatException('回收站记录不存在。');
      database.execute(
        'DELETE FROM revisions WHERE entity_type = ? AND entity_id = ?',
        [entry.entityType.name, entry.id],
      );
      if (entry.entityType == EntityType.person) {
        database.execute('DELETE FROM people WHERE id = ?', [entry.id]);
      } else {
        database.execute('DELETE FROM events WHERE id = ?', [entry.id]);
      }
      _removeTrash(database, entry.entityType, entry.id);
    });
  });

  Future<void> restoreTrash(TrashEntry entry) => _serialize(() async {
    final database = await _open();
    _transaction(database, () {
      final stored = _readTrash(database)
          .where(
            (item) =>
                item.id == entry.id && item.entityType == entry.entityType,
          )
          .firstOrNull;
      if (stored == null) throw const FormatException('回收站记录不存在。');
      if (entry.entityType == EntityType.person) {
        final person = stored.person;
        if (person == null || person.name.trim().isEmpty) {
          throw const FormatException('人物资料不完整，无法恢复。');
        }
        if (database.select('SELECT id FROM people WHERE id = ?', [
          entry.id,
        ]).isNotEmpty) {
          throw const FormatException('人物 ID 已被当前资料占用。');
        }
        _writePerson(database, person);
      } else {
        final event = stored.event;
        if (event == null) throw const FormatException('事件资料不完整，无法恢复。');
        if (database.select('SELECT id FROM events WHERE id = ?', [
          entry.id,
        ]).isNotEmpty) {
          throw const FormatException('事件 ID 已被当前资料占用。');
        }
        _validateEvent(event);
        for (final link in event.people) {
          if (database.select('SELECT id FROM people WHERE id = ?', [
            link.personId,
          ]).isEmpty) {
            throw const FormatException('关联人物已不存在，无法恢复事件。');
          }
        }
        for (final predecessorId in event.previousEventIds) {
          final predecessor = database.select(
            'SELECT id, created_at FROM events WHERE id = ?',
            [predecessorId],
          );
          if (predecessor.isEmpty ||
              !_comesBefore(
                DateTime.parse(predecessor.first['created_at'] as String),
                predecessorId,
                event.createdAt,
                event.id,
              )) {
            throw const FormatException('前序事件已不存在或顺序无效，无法恢复事件。');
          }
        }
        _writeEvent(database, event);
      }
      _removeTrash(database, entry.entityType, entry.id);
      _removeTombstone(database, entry.entityType, entry.id);
    });
  });

  Future<ImportPreview> preview(Archive imported) async {
    final current = await load();
    return _preview(current, imported);
  }

  Future<void> replace(Archive imported) => _serialize(() async {
    _validateArchive(imported);
    final database = await _open();
    _transaction(database, () => _replaceArchive(database, imported));
  });

  Future<void> savePerson(Person person) => _serialize(() async {
    final database = await _open();
    _transaction(database, () {
      final exists = database.select('SELECT id FROM people WHERE id = ?', [
        person.id,
      ]).isNotEmpty;
      _removeTrash(database, EntityType.person, person.id);
      _removeTombstone(database, EntityType.person, person.id);
      _writePerson(database, person);
      _writeRevision(
        database,
        Revision(
          id: _revisionId(),
          entityType: EntityType.person,
          entityId: person.id,
          action: exists ? RevisionAction.update : RevisionAction.create,
          at: person.updatedAt,
          changes: exists
              ? const [ArchiveChange(field: '记录', before: '已修改', after: '已保存')]
              : const [],
        ),
      );
    });
  });

  Future<void> savePersonTags(List<String> tags) =>
      _saveTagCatalog('person_tags', tags);

  Future<void> saveEventTags(List<String> tags) =>
      _saveTagCatalog('event_tags', tags);

  Future<void> saveCustomTags(List<String> tags) => _serialize(() async {
    final database = await _open();
    final normalized = _normalizeTags(tags);
    _transaction(database, () {
      _writeMetadataTags(database, 'custom_tags', normalized);
      _writeMetadataTags(database, 'person_tags', normalized);
      _writeMetadataTags(database, 'event_tags', normalized);
    });
  });

  Future<void> _saveTagCatalog(String key, List<String> tags) =>
      _serialize(() async {
        final database = await _open();
        _transaction(
          database,
          () => _writeMetadataTags(database, key, _normalizeTags(tags)),
        );
      });

  Future<void> saveEvent(EventItem event) => _serialize(() async {
    _validateEvent(event);
    final database = await _open();
    _transaction(database, () {
      final missingPeople = event.people
          .where(
            (link) => database.select('SELECT id FROM people WHERE id = ?', [
              link.personId,
            ]).isEmpty,
          )
          .toList();
      if (missingPeople.isNotEmpty) throw const FormatException('关联人物不存在。');
      final exists = database.select('SELECT id FROM events WHERE id = ?', [
        event.id,
      ]).isNotEmpty;
      for (final predecessorId in event.previousEventIds) {
        final predecessor = database.select(
          'SELECT id, created_at FROM events WHERE id = ?',
          [predecessorId],
        );
        if (predecessor.isEmpty) {
          throw const FormatException('关联的前序事件不存在。');
        }
        if (!_comesBefore(
          DateTime.parse(predecessor.first['created_at'] as String),
          predecessorId,
          event.createdAt,
          event.id,
        )) {
          throw const FormatException('只能关联创建时间更早的事件。');
        }
      }
      _removeTrash(database, EntityType.event, event.id);
      _removeTombstone(database, EntityType.event, event.id);
      _writeEvent(database, event);
      _writeRevision(
        database,
        Revision(
          id: _revisionId(),
          entityType: EntityType.event,
          entityId: event.id,
          action: exists ? RevisionAction.update : RevisionAction.create,
          at: event.updatedAt,
          changes: exists
              ? const [ArchiveChange(field: '记录', before: '已修改', after: '已保存')]
              : const [],
        ),
      );
    });
  });

  Future<bool> deletePerson(String id) => _serialize(() async {
    final database = await _open();
    return _transaction(database, () {
      if (database.select(
        'SELECT event_id FROM event_people WHERE person_id = ? LIMIT 1',
        [id],
      ).isNotEmpty) {
        return false;
      }
      final rows = database.select('SELECT * FROM people WHERE id = ?', [id]);
      if (rows.isEmpty) return false;
      final deletedAt = DateTime.now().toUtc();
      _writeTrash(database, [
        ..._readTrash(database).where(
          (entry) => !(entry.entityType == EntityType.person && entry.id == id),
        ),
        TrashEntry(
          id: id,
          entityType: EntityType.person,
          deletedAt: deletedAt,
          person: _personFromRow(rows.first),
        ),
      ]);
      _writeTombstones(database, [
        ..._readTombstones(database).where(
          (entry) => !(entry.entityType == EntityType.person && entry.id == id),
        ),
        SyncTombstone(
          id: id,
          entityType: EntityType.person,
          deletedAt: deletedAt,
        ),
      ]);
      database.execute(
        "DELETE FROM revisions WHERE entity_type = 'person' AND entity_id = ?",
        [id],
      );
      database.execute('DELETE FROM people WHERE id = ?', [id]);
      return true;
    });
  });

  Future<void> deleteEvent(String id) => _serialize(() async {
    final database = await _open();
    _transaction(database, () {
      final rows = database.select('SELECT * FROM events WHERE id = ?', [id]);
      if (rows.isEmpty) return;
      final deletedAt = DateTime.now().toUtc();
      _writeTrash(database, [
        ..._readTrash(database).where(
          (entry) => !(entry.entityType == EntityType.event && entry.id == id),
        ),
        TrashEntry(
          id: id,
          entityType: EntityType.event,
          deletedAt: deletedAt,
          event: _eventFromRow(database, rows.first),
        ),
      ]);
      _writeTombstones(database, [
        ..._readTombstones(database).where(
          (entry) => !(entry.entityType == EntityType.event && entry.id == id),
        ),
        SyncTombstone(
          id: id,
          entityType: EntityType.event,
          deletedAt: deletedAt,
        ),
      ]);
      database.execute(
        "DELETE FROM revisions WHERE entity_type = 'event' AND entity_id = ?",
        [id],
      );
      database.execute('DELETE FROM events WHERE id = ?', [id]);
    });
  });

  Future<void> transitionEvent(
    String id,
    EventStatus next,
  ) => _serialize(() async {
    final database = await _open();
    _transaction(database, () {
      final rows = database.select('SELECT * FROM events WHERE id = ?', [id]);
      if (rows.isEmpty) throw const FormatException('事件不存在。');
      final current = _eventFromRow(database, rows.first);
      if (!_allowedTransition(current.status, next)) {
        throw FormatException(
          '${current.status.label}不能直接变更为${next.label}，请在编辑器中纠正状态。',
        );
      }
      final updated = current.copyWith(status: next, updatedAt: DateTime.now());
      _validateEvent(updated);
      _writeEvent(database, updated);
      _writeRevision(
        database,
        Revision(
          id: _revisionId(),
          entityType: EntityType.event,
          entityId: id,
          action: RevisionAction.update,
          at: updated.updatedAt,
          changes: [
            ArchiveChange(
              field: '状态',
              before: current.status.label,
              after: next.label,
            ),
          ],
        ),
      );
    });
  });

  Future<void> close() async {
    _database?.dispose();
    _database = null;
  }

  Future<T> _serialize<T>(FutureOr<T> Function() operation) {
    final result = _writes.then((_) => operation());
    _writes = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  int _schemaVersion(Database database) =>
      (database.select('PRAGMA user_version').single['user_version'] as int);

  bool _tableExists(Database database, String name) => database.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [name],
  ).isNotEmpty;

  void _createSchema(Database database) {
    database.execute('''
      CREATE TABLE IF NOT EXISTS people (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        bio TEXT NOT NULL,
        tags TEXT NOT NULL,
        notes TEXT NOT NULL,
        sources TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS events (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        precision TEXT NOT NULL,
        start TEXT NOT NULL,
        end_date TEXT,
        place TEXT NOT NULL,
        description TEXT NOT NULL,
        tags TEXT NOT NULL,
        sources TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'completed',
        images TEXT NOT NULL DEFAULT '[]'
      );
      CREATE TABLE IF NOT EXISTS event_people (
        event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
        person_id TEXT NOT NULL REFERENCES people(id) ON DELETE RESTRICT,
        role TEXT NOT NULL,
        PRIMARY KEY (event_id, person_id)
      );
      CREATE TABLE IF NOT EXISTS revisions (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        action TEXT NOT NULL,
        at TEXT NOT NULL,
        changes TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');
    _createRelationsTable(database);
  }

  void _createRelationsTable(Database database) => database.execute('''
    CREATE TABLE IF NOT EXISTS event_relations (
      event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
      predecessor_event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
      UNIQUE (event_id, predecessor_event_id)
    )
  ''');

  void _replaceArchive(Database database, Archive archive) {
    database.execute(
      'DELETE FROM event_relations; DELETE FROM event_people; DELETE FROM revisions; DELETE FROM events; DELETE FROM people;',
    );
    for (final person in archive.people) {
      _writePerson(database, person);
    }
    for (final event in archive.events) {
      _writeEvent(database, event, writeRelations: false);
    }
    for (final event in archive.events) {
      _writeEventRelations(database, event);
    }
    for (final revision in archive.revisions) {
      _writeRevision(database, revision);
    }
    final personTags = archive.effectivePersonTags;
    final eventTags = archive.effectiveEventTags;
    final allTags = {...personTags, ...eventTags}.toList()..sort();
    _writeMetadataTags(database, 'custom_tags', allTags);
    _writeMetadataTags(database, 'person_tags', personTags);
    _writeMetadataTags(database, 'event_tags', eventTags);
    final personIds = archive.people.map((person) => person.id).toSet();
    final eventIds = archive.events.map((event) => event.id).toSet();
    _writeTrash(
      database,
      _readTrash(database).where((entry) {
        return entry.entityType == EntityType.person
            ? !personIds.contains(entry.id)
            : !eventIds.contains(entry.id);
      }).toList(),
    );
    _writeTombstones(
      database,
      _readTombstones(database).where((entry) {
        return entry.entityType == EntityType.person
            ? !personIds.contains(entry.id)
            : !eventIds.contains(entry.id);
      }).toList(),
    );
  }

  List<TrashEntry> _readTrash(Database database) {
    final rows = database.select(
      "SELECT value FROM metadata WHERE key = 'trash_bin'",
    );
    if (rows.isEmpty) return [];
    try {
      final value = jsonDecode(rows.single['value'] as String);
      return value is List
          ? value
                .whereType<Map>()
                .map(
                  (item) =>
                      TrashEntry.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  List<SyncTombstone> _readTombstones(Database database) {
    final rows = database.select(
      "SELECT value FROM metadata WHERE key = 'sync_tombstones'",
    );
    if (rows.isEmpty) return [];
    try {
      final value = jsonDecode(rows.single['value'] as String);
      return value is List
          ? value
                .whereType<Map>()
                .map(
                  (item) =>
                      SyncTombstone.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  void _writeTrash(Database database, List<TrashEntry> entries) =>
      _writeMetadataJson(
        database,
        'trash_bin',
        entries.map((entry) => entry.toJson()).toList(),
      );

  void _writeTombstones(Database database, List<SyncTombstone> entries) =>
      _writeMetadataJson(
        database,
        'sync_tombstones',
        entries.map((entry) => entry.toJson()).toList(),
      );

  void _writeMetadataJson(Database database, String key, Object value) =>
      database.execute(
        'INSERT INTO metadata (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, jsonEncode(value)],
      );

  void _removeTrash(Database database, EntityType type, String id) =>
      _writeTrash(
        database,
        _readTrash(database)
            .where((entry) => !(entry.entityType == type && entry.id == id))
            .toList(),
      );

  void _removeTombstone(Database database, EntityType type, String id) =>
      _writeTombstones(
        database,
        _readTombstones(database)
            .where((entry) => !(entry.entityType == type && entry.id == id))
            .toList(),
      );

  List<String> _metadataTags(
    Database database,
    String key, {
    List<String> fallback = const [],
  }) {
    final rows = database.select('SELECT value FROM metadata WHERE key = ?', [
      key,
    ]);
    if (rows.isEmpty) return fallback;
    try {
      final value = jsonDecode(rows.single['value'] as String);
      return value is List ? value.whereType<String>().toList() : fallback;
    } catch (_) {
      return fallback;
    }
  }

  List<String> _normalizeTags(List<String> tags) =>
      tags
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  void _writeMetadataTags(Database database, String key, List<String> tags) =>
      database.execute(
        'INSERT INTO metadata (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, jsonEncode(_normalizeTags(tags))],
      );

  void _writePerson(Database database, Person person) => database.execute(
    '''
    INSERT OR REPLACE INTO people (id, name, bio, tags, notes, sources, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  ''',
    [
      person.id,
      person.name,
      person.bio,
      jsonEncode(person.tags),
      person.notes,
      jsonEncode(person.sources),
      person.createdAt.toIso8601String(),
      person.updatedAt.toIso8601String(),
    ],
  );

  void _writeEvent(
    Database database,
    EventItem event, {
    bool writeRelations = true,
  }) {
    database.execute(
      '''
      INSERT INTO events (id, title, precision, start, end_date, place, description, tags, sources, created_at, updated_at, status, images)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        precision = excluded.precision,
        start = excluded.start,
        end_date = excluded.end_date,
        place = excluded.place,
        description = excluded.description,
        tags = excluded.tags,
        sources = excluded.sources,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        status = excluded.status,
        images = excluded.images
    ''',
      [
        event.id,
        event.title,
        event.precision.name,
        event.start,
        event.end,
        event.place,
        event.description,
        jsonEncode(event.tags),
        jsonEncode(event.sources),
        event.createdAt.toIso8601String(),
        event.updatedAt.toIso8601String(),
        event.status.name,
        jsonEncode(event.images),
      ],
    );
    database.execute('DELETE FROM event_people WHERE event_id = ?', [event.id]);
    for (final link in event.people) {
      database.execute(
        'INSERT INTO event_people (event_id, person_id, role) VALUES (?, ?, ?)',
        [event.id, link.personId, link.role.name],
      );
    }
    if (writeRelations) _writeEventRelations(database, event);
  }

  void _writeEventRelations(Database database, EventItem event) {
    database.execute('DELETE FROM event_relations WHERE event_id = ?', [
      event.id,
    ]);
    for (final predecessorId in event.previousEventIds) {
      database.execute(
        'INSERT INTO event_relations (event_id, predecessor_event_id) VALUES (?, ?)',
        [event.id, predecessorId],
      );
    }
  }

  void _writeRevision(Database database, Revision revision) => database.execute(
    '''
    INSERT OR REPLACE INTO revisions (id, entity_type, entity_id, action, at, changes)
    VALUES (?, ?, ?, ?, ?, ?)
  ''',
    [
      revision.id,
      revision.entityType.name,
      revision.entityId,
      revision.action.name,
      revision.at.toIso8601String(),
      jsonEncode(revision.changes.map((change) => change.toJson()).toList()),
    ],
  );

  Person _personFromRow(Row row) => Person(
    id: row['id'] as String,
    name: row['name'] as String,
    bio: row['bio'] as String,
    tags: _strings(row['tags'] as String),
    notes: row['notes'] as String,
    sources: _strings(row['sources'] as String),
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );

  EventItem _eventFromRow(Database database, Row row) => EventItem(
    id: row['id'] as String,
    title: row['title'] as String,
    precision: Precision.values.byName(row['precision'] as String),
    start: row['start'] as String,
    end: row['end_date'] as String?,
    place: row['place'] as String,
    description: row['description'] as String,
    tags: _strings(row['tags'] as String),
    sources: _strings(row['sources'] as String),
    people: database
        .select('SELECT person_id, role FROM event_people WHERE event_id = ?', [
          row['id'],
        ])
        .map(
          (link) => PersonLink(
            personId: link['person_id'] as String,
            role: _roleFromName(link['role'] as String),
          ),
        )
        .toList(),
    status: _eventStatusFromName(row['status'] as String),
    images: (jsonDecode(row['images'] as String) as List).cast<String>(),
    previousEventIds: database
        .select(
          'SELECT predecessor_event_id FROM event_relations WHERE event_id = ? ORDER BY predecessor_event_id',
          [row['id']],
        )
        .map((link) => link['predecessor_event_id'] as String)
        .toList(),
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );

  Revision _revisionFromRow(Row row) => Revision(
    id: row['id'] as String,
    entityType: EntityType.values.byName(row['entity_type'] as String),
    entityId: row['entity_id'] as String,
    action: RevisionAction.values.byName(row['action'] as String),
    at: DateTime.parse(row['at'] as String),
    changes: (jsonDecode(row['changes'] as String) as List)
        .map(
          (item) =>
              ArchiveChange.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );

  ImportPreview _preview(Archive current, Archive imported) {
    var add = 0;
    var duplicate = 0;
    var conflict = 0;
    void count<T>(
      Iterable<T> currentItems,
      Iterable<T> importedItems,
      String Function(T) id,
      Map<String, dynamic> Function(T) json,
    ) {
      final byId = {
        for (final item in currentItems) id(item): jsonEncode(json(item)),
      };
      for (final item in importedItems) {
        final before = byId[id(item)];
        if (before == null) {
          add++;
        } else if (before == jsonEncode(json(item))) {
          duplicate++;
        } else {
          conflict++;
        }
      }
    }

    count(
      current.people,
      imported.people,
      (person) => person.id,
      (person) => person.toJson(),
    );
    count(
      current.events,
      imported.events,
      (event) => event.id,
      (event) => event.toJson(),
    );
    return ImportPreview(add: add, duplicate: duplicate, conflict: conflict);
  }

  void _validateArchive(Archive archive) {
    final ids = <String>{};
    for (final person in archive.people) {
      if (person.id.isEmpty ||
          person.name.trim().isEmpty ||
          !ids.add(person.id)) {
        throw const FormatException('人物资料不完整或存在重复 ID。');
      }
    }
    final eventIds = <String>{};
    for (final event in archive.events) {
      if (event.id.isEmpty ||
          event.title.trim().isEmpty ||
          !eventIds.add(event.id)) {
        throw const FormatException('事件资料不完整或存在重复 ID。');
      }
      _validateEvent(event);
      if (event.people.any((link) => !ids.contains(link.personId))) {
        throw const FormatException('事件关联了不存在的人物。');
      }
      final previousIds = event.previousEventIds.toSet();
      if (previousIds.length != event.previousEventIds.length ||
          previousIds.contains(event.id)) {
        throw const FormatException('事件前序关联重复或关联了自身。');
      }
      for (final predecessorId in previousIds) {
        final predecessor = archive.events
            .where((item) => item.id == predecessorId)
            .firstOrNull;
        if (predecessor == null) {
          throw const FormatException('关联的前序事件不存在。');
        }
        if (!_comesBefore(
          predecessor.createdAt,
          predecessor.id,
          event.createdAt,
          event.id,
        )) {
          throw const FormatException('只能关联创建时间更早的事件。');
        }
      }
    }
  }

  void _validateEvent(EventItem event) {
    if (event.title.trim().isEmpty || event.people.isEmpty) {
      throw const FormatException('请填写事件标题并关联至少一位人物。');
    }
    final previousIds = event.previousEventIds.toSet();
    if (previousIds.length != event.previousEventIds.length ||
        previousIds.contains(event.id)) {
      throw const FormatException('事件前序关联重复或关联了自身。');
    }
    if (event.status != EventStatus.scheduled &&
        event.status != EventStatus.cancelled &&
        event.start.isEmpty) {
      throw const FormatException('进行中或已结束事件必须填写时间。');
    }
    if (event.status == EventStatus.scheduled &&
        event.start.isNotEmpty &&
        !_isLocalDay(event.start)) {
      throw const FormatException('预定日期必须精确到日。');
    }
    if (event.status == EventStatus.scheduled &&
        (event.precision != Precision.day || event.end?.isNotEmpty == true)) {
      throw const FormatException('预定事件只能使用单日日期。');
    }
    if (event.precision == Precision.range &&
        event.end != null &&
        event.end!.isNotEmpty &&
        event.end!.compareTo(event.start) < 0) {
      throw const FormatException('结束时间不能早于开始时间。');
    }
  }

  bool _isLocalDay(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null || value.length != 10) return false;
    final expected =
        '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
    return expected == value;
  }

  bool _comesBefore(
    DateTime leftAt,
    String leftId,
    DateTime rightAt,
    String rightId,
  ) =>
      leftAt.isBefore(rightAt) ||
      (leftAt.isAtSameMomentAs(rightAt) && leftId.compareTo(rightId) < 0);

  bool _allowedTransition(EventStatus from, EventStatus to) => switch (from) {
    EventStatus.scheduled =>
      to == EventStatus.active || to == EventStatus.cancelled,
    EventStatus.active =>
      to == EventStatus.completed || to == EventStatus.cancelled,
    EventStatus.completed || EventStatus.cancelled => false,
  };

  T _transaction<T>(Database database, T Function() action) {
    database.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      database.execute('COMMIT');
      return result;
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }
}

List<String> _strings(String source) =>
    (jsonDecode(source) as List).cast<String>();

Role _roleFromName(String value) => switch (value) {
  'organizer' || 'subject' => Role.organizer,
  'participant' || 'witness' || 'mentioned' => Role.participant,
  _ => throw FormatException('不支持的人物角色：$value'),
};

EventStatus _eventStatusFromName(String value) => switch (value) {
  'scheduled' || '预定' => EventStatus.scheduled,
  'active' || '进行中' => EventStatus.active,
  'completed' || '已结束' => EventStatus.completed,
  'cancelled' || 'canceled' || '已取消' => EventStatus.cancelled,
  _ => throw FormatException('不支持的事件状态：$value'),
};

String _revisionId() => 'r-${DateTime.now().microsecondsSinceEpoch}';
