import 'package:flutter_test/flutter_test.dart';
import 'package:person_event_atlas/archive.dart';

void main() {
  test('round-trips a version 1 archive', () {
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

    expect(decoded.events.single.people.single.role, Role.subject);
  });
}
