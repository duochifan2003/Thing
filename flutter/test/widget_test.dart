import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:person_event_atlas/archive_repository.dart';
import 'package:person_event_atlas/main.dart';

void main() {
  testWidgets('uses a navigation rail on a wide window', (tester) async {
    final repository = ArchiveRepository(databasePath: ':memory:');
    addTearDown(repository.close);

    await tester.binding.setSurfaceSize(const Size(1100, 800));
    await tester.pumpWidget(PersonEventAtlasApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('事件时间线'), findsOneWidget);
  });

  testWidgets('uses bottom navigation on a narrow window', (tester) async {
    final repository = ArchiveRepository(databasePath: ':memory:');
    addTearDown(repository.close);

    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pumpWidget(PersonEventAtlasApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
