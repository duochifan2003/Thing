import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'archive.dart';

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
        updated_at TEXT NOT NULL
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
      PRAGMA user_version = 1;
    ''');
    _database = database;
    if (database
        .select("SELECT value FROM metadata WHERE key = 'initialized'")
        .isEmpty) {
      _transaction(database, () {
        _replaceArchive(database, seedArchive);
        database.execute(
          "INSERT INTO metadata (key, value) VALUES ('initialized', 'true')",
        );
      });
    }
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
    return Archive(people: people, events: events, revisions: revisions);
  }

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
    final deleted = _transaction(database, () {
      if (database.select(
        'SELECT event_id FROM event_people WHERE person_id = ? LIMIT 1',
        [id],
      ).isNotEmpty)
        return false;
      database.execute('DELETE FROM people WHERE id = ?', [id]);
      return true;
    });
    return deleted;
  });

  Future<void> deleteEvent(String id) => _serialize(() async {
    final database = await _open();
    _transaction(
      database,
      () => database.execute('DELETE FROM events WHERE id = ?', [id]),
    );
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

  void _replaceArchive(Database database, Archive archive) {
    database.execute(
      'DELETE FROM event_people; DELETE FROM revisions; DELETE FROM events; DELETE FROM people;',
    );
    for (final person in archive.people) {
      _writePerson(database, person);
    }
    for (final event in archive.events) {
      _writeEvent(database, event);
    }
    for (final revision in archive.revisions) {
      _writeRevision(database, revision);
    }
  }

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

  void _writeEvent(Database database, EventItem event) {
    database.execute(
      '''
      INSERT OR REPLACE INTO events (id, title, precision, start, end_date, place, description, tags, sources, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      ],
    );
    database.execute('DELETE FROM event_people WHERE event_id = ?', [event.id]);
    for (final link in event.people) {
      database.execute(
        'INSERT INTO event_people (event_id, person_id, role) VALUES (?, ?, ?)',
        [event.id, link.personId, link.role.name],
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
          !ids.add(person.id))
        throw const FormatException('人物资料不完整或存在重复 ID。');
    }
    final eventIds = <String>{};
    for (final event in archive.events) {
      if (event.id.isEmpty ||
          event.title.trim().isEmpty ||
          !eventIds.add(event.id))
        throw const FormatException('事件资料不完整或存在重复 ID。');
      _validateEvent(event);
      if (event.people.any((link) => !ids.contains(link.personId)))
        throw const FormatException('事件关联了不存在的人物。');
    }
  }

  void _validateEvent(EventItem event) {
    if (event.title.trim().isEmpty ||
        event.start.isEmpty ||
        event.people.isEmpty)
      throw const FormatException('请填写事件标题、时间并关联至少一位人物。');
    if (event.precision == Precision.range &&
        event.end != null &&
        event.end!.isNotEmpty &&
        event.end!.compareTo(event.start) < 0) {
      throw const FormatException('结束时间不能早于开始时间。');
    }
  }

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

String _revisionId() => 'r-${DateTime.now().microsecondsSinceEpoch}';
