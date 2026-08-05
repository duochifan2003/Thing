import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:person_event_atlas/app_settings.dart';
import 'package:path/path.dart' as path;
import 'package:person_event_atlas/archive.dart';
import 'package:person_event_atlas/archive_repository.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late ArchiveRepository repository;

  setUp(() => repository = ArchiveRepository(databasePath: ':memory:'));
  tearDown(() => repository.close());

  test(
    'stores people, events, links, and imported revisions in SQLite',
    () async {
      final archive = Archive(
        people: [_person('p-1')],
        events: [_event('e-1', 'p-1')],
        revisions: [
          Revision(
            id: 'r-1',
            entityType: EntityType.event,
            entityId: 'e-1',
            action: RevisionAction.create,
            at: DateTime(2025),
            changes: const [],
          ),
        ],
      );

      await repository.replace(archive);
      final loaded = await repository.load();

      expect(loaded.people.single.name, '林岚');
      expect(loaded.events.single.people.single.personId, 'p-1');
      expect(loaded.revisions.single.id, 'r-1');
    },
  );

  test('stores and replaces event image data in SQLite', () async {
    await repository.replace(
      Archive(
        people: [_person('p-1')],
        events: [
          _event('e-1', 'p-1').copyWith(images: const ['aW1hZ2UtYQ==']),
        ],
      ),
    );
    expect((await repository.load()).events.single.images, ['aW1hZ2UtYQ==']);

    await repository.saveEvent(
      _event('e-1', 'p-1').copyWith(images: const ['aW1hZ2UtYg==']),
    );

    expect((await repository.load()).events.single.images, ['aW1hZ2UtYg==']);
  });

  test('starts a new database without sample archive data', () async {
    final loaded = await repository.load();

    expect(loaded.people, isEmpty);
    expect(loaded.events, isEmpty);
    expect(loaded.revisions, isEmpty);
    expect(loaded.customTags, isEmpty);
  });

  test('persists custom tags in metadata', () async {
    await repository.replace(
      Archive(people: const [], events: const [], customTags: const ['旧标签']),
    );
    await repository.saveCustomTags(['厦门', '  厦门  ', '长期项目']);

    expect((await repository.load()).customTags, ['厦门', '长期项目']);
  });

  test('persists person and event tag catalogs separately', () async {
    await repository.replace(
      Archive(
        people: const [],
        events: const [],
        personTags: const ['家人'],
        eventTags: const ['旅行'],
      ),
    );
    await repository.savePersonTags(['家人', '同事']);
    await repository.saveEventTags(['旅行']);

    final loaded = await repository.load();
    expect(loaded.personTags, ['同事', '家人']);
    expect(loaded.eventTags, ['旅行']);
    expect(loaded.customTags, ['同事', '家人', '旅行']);
  });

  test('loads default settings and persists settings in metadata', () async {
    expect((await repository.loadSettings()).themeMode, AppThemeMode.system);
    expect(
      (await repository.loadSettings()).primaryColor,
      AppPrimaryColor.berryRedOat,
    );
    expect((await repository.loadSettings()).colorShadows, isTrue);
    expect((await repository.loadSettings()).defaultPrecision, Precision.day);

    const settings = AppSettings(
      themeMode: AppThemeMode.dark,
      primaryColor: AppPrimaryColor.royalBlueYellow,
      colorShadows: false,
      defaultPrecision: Precision.range,
      syncDirectory: '/tmp/shared',
      syncDirectoryBookmark: 'bookmark-data',
    );
    await repository.saveSettings(settings);

    final loaded = await repository.loadSettings();
    expect(loaded.themeMode, AppThemeMode.dark);
    expect(loaded.primaryColor, AppPrimaryColor.royalBlueYellow);
    expect(loaded.colorShadows, isFalse);
    expect(loaded.defaultPrecision, Precision.range);
    expect(loaded.syncDirectory, '/tmp/shared');
    expect(loaded.syncDirectoryBookmark, 'bookmark-data');
  });

  test('round-trips every color pairing in local settings', () async {
    for (final color in AppPrimaryColor.values) {
      await repository.saveSettings(AppSettings(primaryColor: color));
      expect((await repository.loadSettings()).primaryColor, color);
    }
  });

  test('maps retired palette values to the remaining palettes', () {
    expect(
      AppSettings.fromJson({'primaryColor': 'oceanBlue'}).primaryColor,
      AppPrimaryColor.royalBlueYellow,
    );
    expect(
      AppSettings.fromJson({'primaryColor': 'terracotta'}).primaryColor,
      AppPrimaryColor.berryRedOat,
    );
    expect(AppPrimaryColor.values, [
      AppPrimaryColor.berryRedOat,
      AppPrimaryColor.royalBlueYellow,
    ]);
  });

  test(
    'falls back to defaults for damaged settings and survives restart',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'event-atlas-settings-',
      );
      final databasePath = path.join(root.path, 'archive.sqlite');
      final first = ArchiveRepository(databasePath: databasePath);
      await first.saveSettings(
        const AppSettings(
          themeMode: AppThemeMode.light,
          primaryColor: AppPrimaryColor.berryRedOat,
          defaultPrecision: Precision.month,
        ),
      );
      await first.close();

      final restarted = ArchiveRepository(databasePath: databasePath);
      expect(
        (await restarted.loadSettings()).defaultPrecision,
        Precision.month,
      );
      await restarted.close();

      final raw = sqlite3.open(databasePath);
      raw.execute(
        "UPDATE metadata SET value = 'not-json' WHERE key = 'app_settings'",
      );
      raw.dispose();

      final damaged = ArchiveRepository(databasePath: databasePath);
      addTearDown(() async {
        await damaged.close();
        await root.delete(recursive: true);
      });
      expect(await damaged.loadSettings(), isA<AppSettings>());
      expect((await damaged.loadSettings()).themeMode, AppThemeMode.system);
      expect(
        (await damaged.loadSettings()).primaryColor,
        AppPrimaryColor.berryRedOat,
      );
      expect((await damaged.loadSettings()).defaultPrecision, Precision.day);
    },
  );

  test('archive replacement preserves local settings', () async {
    const settings = AppSettings(
      themeMode: AppThemeMode.dark,
      primaryColor: AppPrimaryColor.royalBlueYellow,
      defaultPrecision: Precision.year,
    );
    await repository.saveSettings(settings);
    await repository.replace(
      Archive(
        people: [_person('p-1')],
        events: const [],
        customTags: const ['档案标签'],
      ),
    );

    expect(await repository.loadSettings(), isA<AppSettings>());
    final loaded = await repository.loadSettings();
    expect(loaded.themeMode, AppThemeMode.dark);
    expect(loaded.primaryColor, AppPrimaryColor.royalBlueYellow);
    expect(loaded.defaultPrecision, Precision.year);
    expect((await repository.load()).customTags, ['档案标签']);
  });

  test('saves new and existing events with matching revisions', () async {
    await repository.replace(
      Archive(people: [_person('p-1')], events: const []),
    );
    final event = _event('e-1', 'p-1');

    await repository.saveEvent(event);
    await repository.saveEvent(
      event.copyWith(title: '更新后的访谈', updatedAt: DateTime(2025, 2)),
    );

    final loaded = await repository.load();
    expect(loaded.events.single.title, '更新后的访谈');
    expect(loaded.revisions.map((revision) => revision.action).toList(), [
      RevisionAction.create,
      RevisionAction.update,
    ]);
    expect(loaded.revisions.last.changes.single.field, '记录');
  });

  test(
    'keeps existing data when an event transaction fails validation',
    () async {
      await repository.replace(
        Archive(people: [_person('p-1')], events: const []),
      );

      await expectLater(
        repository.saveEvent(_event('e-1', 'missing')),
        throwsA(isA<FormatException>()),
      );
      final loaded = await repository.load();

      expect(loaded.events, isEmpty);
      expect(loaded.people, hasLength(1));
    },
  );

  test('blocks deleting a person who remains linked to an event', () async {
    await repository.replace(
      Archive(people: [_person('p-1')], events: [_event('e-1', 'p-1')]),
    );

    expect(await repository.deletePerson('p-1'), isFalse);
    expect((await repository.load()).people, hasLength(1));
  });

  test('deletes an unlinked person', () async {
    await repository.replace(
      Archive(people: [_person('p-1')], events: const []),
    );

    expect(await repository.deletePerson('p-1'), isTrue);
    expect((await repository.load()).people, isEmpty);
  });

  test('rejects reversed date ranges', () async {
    await repository.replace(
      Archive(people: [_person('p-1')], events: const []),
    );
    final invalid = EventItem(
      id: 'e',
      title: '区间',
      precision: Precision.range,
      start: '2025-06-01',
      end: '2025-05-01',
      place: '',
      description: '',
      tags: const [],
      sources: const [],
      people: const [PersonLink(personId: 'p-1', role: Role.organizer)],
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

    await expectLater(
      repository.saveEvent(invalid),
      throwsA(isA<FormatException>()),
    );
  });

  test('previews imports and records new edits as revisions', () async {
    await repository.replace(
      Archive(people: [_person('p-1')], events: const []),
    );
    final preview = await repository.preview(
      Archive(people: [_person('p-1'), _person('p-2')], events: const []),
    );
    await repository.savePerson(_person('p-2'));

    expect(preview.add, 1);
    expect(preview.duplicate, 1);
    expect((await repository.load()).revisions.last.entityId, 'p-2');
  });

  test('counts conflicting imports', () async {
    await repository.replace(
      Archive(people: [_person('p-1')], events: const []),
    );

    final preview = await repository.preview(
      Archive(
        people: [_person('p-1').copyWith(name: '不同人物')],
        events: const [],
      ),
    );

    expect(preview.add, 0);
    expect(preview.duplicate, 0);
    expect(preview.conflict, 1);
  });

  test('creates a missing parent directory for a file database', () async {
    final root = await Directory.systemTemp.createTemp('event-atlas-test-');
    final databasePath = path.join(root.path, 'new', 'archive.sqlite');
    final fileRepository = ArchiveRepository(databasePath: databasePath);
    addTearDown(() async {
      await fileRepository.close();
      await root.delete(recursive: true);
    });

    await fileRepository.load();

    expect(File(databasePath).existsSync(), isTrue);
  });

  test('stores planned status, empty dates, and predecessor links', () async {
    final previous = _event('e-0', 'p-1', createdAt: DateTime(2025, 1, 1));
    final planned = _event(
      'e-1',
      'p-1',
      status: EventStatus.scheduled,
      start: '',
      createdAt: DateTime(2025, 1, 2),
      previousEventIds: const ['e-0'],
    );
    await repository.replace(
      Archive(people: [_person('p-1')], events: [previous, planned]),
    );

    final loaded = await repository.load();
    final actual = loaded.events.singleWhere((event) => event.id == 'e-1');
    expect(actual.status, EventStatus.scheduled);
    expect(actual.dateLabel, '待定');
    expect(actual.previousEventIds, ['e-0']);
  });

  test('enforces the state transition graph', () async {
    await repository.replace(
      Archive(
        people: [_person('p-1')],
        events: [
          _event(
            'e-1',
            'p-1',
            status: EventStatus.scheduled,
            start: '2025-01-01',
          ),
        ],
      ),
    );

    await repository.transitionEvent('e-1', EventStatus.active);
    await repository.transitionEvent('e-1', EventStatus.completed);
    await expectLater(
      repository.transitionEvent('e-1', EventStatus.cancelled),
      throwsA(isA<FormatException>()),
    );
    expect(
      (await repository.load()).events.single.status,
      EventStatus.completed,
    );
  });

  test('allows cancellation and rejects a missing event', () async {
    await repository.replace(
      Archive(
        people: [_person('p-1')],
        events: [
          _event('scheduled', 'p-1', status: EventStatus.scheduled, start: ''),
          _event('active', 'p-1', status: EventStatus.active),
        ],
      ),
    );

    await repository.transitionEvent('scheduled', EventStatus.cancelled);
    await repository.transitionEvent('active', EventStatus.cancelled);

    expect(
      (await repository.load()).events.map((event) => event.status).toSet(),
      {EventStatus.cancelled},
    );
    await expectLater(
      repository.transitionEvent('missing', EventStatus.cancelled),
      throwsA(isA<FormatException>()),
    );
  });

  test('uses event ID as the tie-breaker for predecessor order', () async {
    final createdAt = DateTime(2025, 1, 1);
    await repository.replace(
      Archive(
        people: [_person('p-1')],
        events: [
          _event('a', 'p-1', createdAt: createdAt),
          _event(
            'b',
            'p-1',
            createdAt: createdAt,
            previousEventIds: const ['a'],
          ),
        ],
      ),
    );

    await expectLater(
      repository.saveEvent(
        _event('a', 'p-1', createdAt: createdAt, previousEventIds: const ['b']),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      (await repository.load()).events
          .singleWhere((event) => event.id == 'b')
          .previousEventIds,
      ['a'],
    );
  });

  test('requires a local calendar date for scheduled reminders', () async {
    await repository.replace(
      Archive(people: [_person('p-1')], events: const []),
    );

    await expectLater(
      repository.saveEvent(
        _event(
          'e-1',
          'p-1',
          status: EventStatus.scheduled,
          start: '2025-01-01T00:00:00.000Z',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects missing predecessors when saving an event', () async {
    await repository.replace(
      Archive(people: [_person('p-1')], events: const []),
    );

    await expectLater(
      repository.saveEvent(
        _event('e-1', 'p-1', previousEventIds: const ['missing']),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects malformed archives before writing', () async {
    final person = _person('p-1');
    final invalidArchives = [
      Archive(people: [_person('')], events: const []),
      Archive(
        people: [person.copyWith(name: '  ')],
        events: const [],
      ),
      Archive(people: [person, _person('p-1')], events: const []),
      Archive(people: [person], events: [_event('', 'p-1')]),
      Archive(
        people: [person],
        events: [_event('e-1', 'p-1', title: '  ')],
      ),
      Archive(
        people: [person],
        events: [_event('e-1', 'p-1'), _event('e-1', 'p-1')],
      ),
      Archive(
        people: [person],
        events: [_event('e-1', 'p-1', people: const [])],
      ),
      Archive(people: [person], events: [_event('e-1', 'missing')]),
      Archive(
        people: [person],
        events: [
          _event('e-1', 'p-1', previousEventIds: const ['e-1']),
        ],
      ),
      Archive(
        people: [person],
        events: [
          _event('e-1', 'p-1', previousEventIds: const ['e-0', 'e-0']),
        ],
      ),
      Archive(
        people: [person],
        events: [
          _event('e-1', 'p-1', previousEventIds: const ['missing']),
        ],
      ),
      Archive(
        people: [person],
        events: [
          _event('e-1', 'p-1', status: EventStatus.completed, start: ''),
        ],
      ),
      Archive(
        people: [person],
        events: [
          _event(
            'e-1',
            'p-1',
            status: EventStatus.scheduled,
            precision: Precision.month,
          ),
        ],
      ),
      Archive(
        people: [person],
        events: [
          _event(
            'e-1',
            'p-1',
            status: EventStatus.scheduled,
            end: '2025-03-19',
          ),
        ],
      ),
    ];

    for (final archive in invalidArchives) {
      await expectLater(
        repository.replace(archive),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test(
    'removes predecessor links when permanently deleting an event',
    () async {
      await repository.replace(
        Archive(
          people: [_person('p-1')],
          events: [
            _event('e-0', 'p-1', createdAt: DateTime(2025, 1, 1)),
            _event(
              'e-1',
              'p-1',
              createdAt: DateTime(2025, 1, 2),
              previousEventIds: const ['e-0'],
            ),
          ],
        ),
      );

      await repository.deleteEvent('e-0');

      final loaded = await repository.load();
      expect(loaded.events.single.id, 'e-1');
      expect(loaded.events.single.previousEventIds, isEmpty);
    },
  );

  test(
    'migrates a version 1 database and defaults old events to completed',
    () async {
      final root = await Directory.systemTemp.createTemp('event-atlas-v1-');
      final databasePath = path.join(root.path, 'archive.sqlite');
      final legacy = sqlite3.open(databasePath);
      legacy.execute('''
      CREATE TABLE people (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, bio TEXT NOT NULL,
        tags TEXT NOT NULL, notes TEXT NOT NULL, sources TEXT NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      );
      CREATE TABLE events (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, precision TEXT NOT NULL,
        start TEXT NOT NULL, end_date TEXT, place TEXT NOT NULL,
        description TEXT NOT NULL, tags TEXT NOT NULL, sources TEXT NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      );
      CREATE TABLE event_people (
        event_id TEXT NOT NULL, person_id TEXT NOT NULL, role TEXT NOT NULL,
        PRIMARY KEY (event_id, person_id)
      );
      CREATE TABLE revisions (
        id TEXT PRIMARY KEY, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
        action TEXT NOT NULL, at TEXT NOT NULL, changes TEXT NOT NULL
      );
      CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      PRAGMA user_version = 1;
    ''');
      legacy.execute(
        "INSERT INTO people VALUES ('p-1', '林岚', '', '[]', '', '[]', '2025-01-01T00:00:00.000', '2025-01-01T00:00:00.000')",
      );
      legacy.execute(
        "INSERT INTO events VALUES ('e-1', '旧事件', 'day', '2025-01-01', NULL, '', '', '[]', '[]', '2025-01-01T00:00:00.000', '2025-01-01T00:00:00.000')",
      );
      legacy.execute(
        "INSERT INTO event_people VALUES ('e-1', 'p-1', 'organizer')",
      );
      legacy.execute("INSERT INTO metadata VALUES ('initialized', 'true')");
      legacy.dispose();

      final migrated = ArchiveRepository(databasePath: databasePath);
      addTearDown(() async {
        await migrated.close();
        await root.delete(recursive: true);
      });

      final loaded = await migrated.load();
      expect(loaded.events.single.status, EventStatus.completed);
      expect(loaded.events.single.previousEventIds, isEmpty);
      expect(loaded.events.single.images, isEmpty);

      await migrated.saveEvent(
        loaded.events.single.copyWith(images: const ['b2xkLWltYWdl']),
      );
      expect((await migrated.load()).events.single.images, ['b2xkLWltYWdl']);
    },
  );
}

Person _person(String id) => Person(
  id: id,
  name: '林岚',
  bio: '',
  tags: const [],
  notes: '',
  sources: const [],
  createdAt: DateTime(2025),
  updatedAt: DateTime(2025),
);

EventItem _event(
  String id,
  String personId, {
  String start = '2025-03-18',
  String? end,
  String title = '访谈',
  Precision precision = Precision.day,
  List<PersonLink>? people,
  DateTime? createdAt,
  EventStatus status = EventStatus.completed,
  List<String> previousEventIds = const [],
}) => EventItem(
  id: id,
  title: title,
  precision: precision,
  start: start,
  end: end,
  place: '',
  description: '',
  tags: const [],
  sources: const [],
  people: people ?? [PersonLink(personId: personId, role: Role.organizer)],
  createdAt: createdAt ?? DateTime(2025),
  updatedAt: createdAt ?? DateTime(2025),
  status: status,
  previousEventIds: previousEventIds,
);
