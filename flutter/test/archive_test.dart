import 'package:flutter_test/flutter_test.dart';
import 'package:person_event_atlas/archive.dart';

import 'test_data.dart';

void main() {
  test('round-trips the current archive format', () {
    final decoded = Archive.decode(seedArchive.encode());

    expect(decoded.people.first.name, '林岚');
    expect(
      decoded.events.singleWhere((event) => event.id == 'e-2').dateLabel,
      '2025.04.01 — 2025.05.20',
    );
  });

  test('accepts JSON exports from the Web version', () {
    final decoded = Archive.decode('''
      {"version":1,"people":[{"id":"p","name":"林岚","createdAt":"2025-01-01T00:00:00.000","updatedAt":"2025-01-01T00:00:00.000"}],"events":[{"id":"e","title":"访谈","precision":"day","start":"2025-01-01","createdAt":"2025-01-01T00:00:00.000","updatedAt":"2025-01-01T00:00:00.000","people":[{"personId":"p","role":"当事人"}]}],"revisions":[]}
    ''');

    expect(decoded.events.single.people.single.role, Role.organizer);
    expect(decoded.events.single.status, EventStatus.completed);
  });

  test('round-trips planned status and predecessor links', () {
    final previous = EventItem(
      id: 'previous',
      title: '准备',
      precision: Precision.day,
      start: '2025-01-01',
      place: '',
      description: '',
      tags: const [],
      sources: const [],
      people: const [PersonLink(personId: 'p', role: Role.organizer)],
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
      status: EventStatus.completed,
    );
    final planned = EventItem(
      id: 'planned',
      title: '待定',
      precision: Precision.day,
      start: '',
      place: '',
      description: '',
      tags: const ['工作'],
      sources: const [],
      people: const [PersonLink(personId: 'p', role: Role.organizer)],
      createdAt: DateTime(2025, 1, 2),
      updatedAt: DateTime(2025, 1, 2),
      status: EventStatus.scheduled,
      previousEventIds: const ['previous'],
    );
    final decoded = Archive.decode(
      Archive(people: const [], events: [previous, planned]).encode(),
    );

    expect(decoded.events.last.status, EventStatus.scheduled);
    expect(decoded.events.last.dateLabel, '待定');
    expect(decoded.events.last.previousEventIds, ['previous']);
  });

  test('round-trips custom tags', () {
    final decoded = Archive.decode(
      Archive(
        people: const [],
        events: const [],
        customTags: const ['长期项目', '厦门'],
      ).encode(),
    );

    expect(decoded.customTags, ['长期项目', '厦门']);
  });

  test('keeps person and event tag catalogs separate', () {
    final decoded = Archive.decode(
      Archive(
        people: const [],
        events: const [],
        personTags: const ['家人'],
        eventTags: const ['旅行'],
      ).encode(),
    );

    expect(decoded.personTags, ['家人']);
    expect(decoded.eventTags, ['旅行']);
    expect(decoded.allTagCatalog, ['家人', '旅行']);

    final legacy = Archive.decode(
      '{"version":2,"people":[],"events":[],"customTags":["旧标签"],"revisions":[]}',
    );
    expect(legacy.effectivePersonTags, ['旧标签']);
    expect(legacy.effectiveEventTags, ['旧标签']);
  });

  test('covers model labels, aliases, and copyWith branches', () {
    expect(Precision.values.map((value) => value.label).toList(), [
      '年份',
      '月份',
      '具体日期',
      '起止区间',
    ]);
    expect(Role.organizer.label, '组织者');
    expect(Role.participant.label, '参与者');
    expect(EventStatus.cancelled.label, '已取消');
    expect(EntityType.person.label, '人物');
    expect(EntityType.event.label, '事件');
    expect(RevisionAction.create.label, '创建');
    expect(RevisionAction.update.label, '更新');

    final person = Person(
      id: 'p-1',
      name: '林岚',
      bio: '简介',
      tags: const ['人物'],
      notes: '备注',
      sources: const ['来源'],
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );
    final copiedPerson = person.copyWith(
      name: '新名字',
      bio: '新简介',
      tags: const ['新标签'],
      notes: '新备注',
      sources: const ['新来源'],
      updatedAt: DateTime(2025, 2),
    );
    expect(copiedPerson.name, '新名字');
    expect(copiedPerson.bio, '新简介');
    expect(copiedPerson.tags, ['新标签']);
    expect(copiedPerson.notes, '新备注');
    expect(copiedPerson.sources, ['新来源']);
    expect(copiedPerson.createdAt, person.createdAt);
    expect(copiedPerson.updatedAt, DateTime(2025, 2));

    const roleAliases = <String, Role>{
      '组织者': Role.organizer,
      'organizer': Role.organizer,
      '当事人': Role.organizer,
      'subject': Role.organizer,
      '参与者': Role.participant,
      'participant': Role.participant,
      '见证人': Role.participant,
      'witness': Role.participant,
      '提及者': Role.participant,
      'mentioned': Role.participant,
    };
    for (final entry in roleAliases.entries) {
      expect(
        PersonLink.fromJson({'personId': 'p-1', 'role': entry.key}).role,
        entry.value,
      );
    }
    expect(
      () => PersonLink.fromJson({'personId': 'p-1', 'role': 'unknown'}),
      throwsA(isA<FormatException>()),
    );

    final event = EventItem(
      id: 'e-1',
      title: '事件',
      precision: Precision.range,
      start: '2025-01-01',
      place: '地点',
      description: '描述',
      tags: const ['标签'],
      sources: const ['来源'],
      people: const [PersonLink(personId: 'p-1', role: Role.participant)],
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      status: EventStatus.cancelled,
    );
    expect(event.dateLabel, '2025.01.01 — 至今');
    final copiedEvent = event.copyWith(
      title: '新事件',
      precision: Precision.day,
      start: '2025-02-02',
      clearEnd: true,
      place: '新地点',
      description: '新描述',
      tags: const ['新标签'],
      sources: const ['新来源'],
      people: const [PersonLink(personId: 'p-1', role: Role.organizer)],
      updatedAt: DateTime(2025, 2),
      status: EventStatus.active,
      previousEventIds: const ['e-0'],
    );
    expect(copiedEvent.title, '新事件');
    expect(copiedEvent.precision, Precision.day);
    expect(copiedEvent.start, '2025-02-02');
    expect(copiedEvent.end, isNull);
    expect(copiedEvent.place, '新地点');
    expect(copiedEvent.description, '新描述');
    expect(copiedEvent.tags, ['新标签']);
    expect(copiedEvent.sources, ['新来源']);
    expect(copiedEvent.people.single.role, Role.organizer);
    expect(copiedEvent.status, EventStatus.active);
    expect(copiedEvent.previousEventIds, ['e-0']);

    const statusAliases = <String, EventStatus>{
      '预定': EventStatus.scheduled,
      'scheduled': EventStatus.scheduled,
      '进行中': EventStatus.active,
      'active': EventStatus.active,
      '已结束': EventStatus.completed,
      'completed': EventStatus.completed,
      '已取消': EventStatus.cancelled,
      'cancelled': EventStatus.cancelled,
      'canceled': EventStatus.cancelled,
    };
    for (final entry in statusAliases.entries) {
      expect(
        EventItem.fromJson({...event.toJson(), 'status': entry.key}).status,
        entry.value,
      );
    }
    expect(
      () => EventItem.fromJson({...event.toJson(), 'status': 'unknown'}),
      throwsA(isA<FormatException>()),
    );

    final archive = Archive(
      people: [person],
      events: [event],
      customTags: const ['标签'],
    );
    final copiedArchive = archive.copyWith(
      people: const [],
      events: const [],
      customTags: const ['新标签'],
      revisions: const [],
    );
    expect(copiedArchive.people, isEmpty);
    expect(copiedArchive.events, isEmpty);
    expect(copiedArchive.customTags, ['新标签']);
  });

  test('round-trips revisions and rejects unsupported archive values', () {
    final revision = Revision(
      id: 'r-1',
      entityType: EntityType.event,
      entityId: 'e-1',
      action: RevisionAction.update,
      at: DateTime(2025),
      changes: const [ArchiveChange(field: '地点', before: '旧', after: '新')],
    );
    final decoded = Revision.fromJson(revision.toJson());

    expect(decoded.entityType, EntityType.event);
    expect(decoded.action, RevisionAction.update);
    expect(decoded.changes.single.after, '新');
    expect(ArchiveChange.fromJson({'field': '状态'}).before, '—');
    expect(ArchiveChange.fromJson({'field': '状态'}).after, '—');

    final base = revision.toJson();
    for (final value in ['人物', 'person']) {
      expect(
        Revision.fromJson({...base, 'entityType': value}).entityType,
        EntityType.person,
      );
    }
    for (final value in ['创建', 'create']) {
      expect(
        Revision.fromJson({...base, 'action': value}).action,
        RevisionAction.create,
      );
    }
    expect(
      () => Revision.fromJson({...base, 'entityType': 'unknown'}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => Revision.fromJson({...base, 'action': 'unknown'}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => Archive.decode('{"version":99,"people":[],"events":[]}'),
      throwsA(isA<FormatException>()),
    );
  });
}
