import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:person_event_atlas/archive.dart';
import 'package:person_event_atlas/archive_repository.dart';

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

EventItem _event(String id, String personId) => EventItem(
  id: id,
  title: '访谈',
  precision: Precision.day,
  start: '2025-03-18',
  place: '',
  description: '',
  tags: const [],
  sources: const [],
  people: [PersonLink(personId: personId, role: Role.organizer)],
  createdAt: DateTime(2025),
  updatedAt: DateTime(2025),
);
