import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:person_event_atlas/archive.dart';
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
    expect(find.text('标签管理'), findsOneWidget);
  });

  testWidgets('adds a custom tag from the tag page', (tester) async {
    List<String>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomTagsPage(
            customTags: const [],
            eventCounts: const {},
            onChanged: (tags) async => saved = tags,
            onDelete: (_) async {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '长期项目');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(saved, ['长期项目']);
  });

  testWidgets('shows only custom tags and deletes an unused tag', (
    tester,
  ) async {
    List<String>? saved;
    String? deleted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomTagsPage(
            customTags: const ['旧标签'],
            eventCounts: const {'旧标签': 3},
            onChanged: (tags) async => saved = tags,
            onDelete: (tag) async => deleted = tag,
          ),
        ),
      ),
    );

    expect(find.text('预设标签'), findsNothing);
    expect(find.text('#旧标签'), findsOneWidget);
    expect(find.text('关联 3 个事件'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(deleted, '旧标签');
    expect(saved, isNull);
  });

  testWidgets('uses bottom navigation on a narrow window', (tester) async {
    final repository = ArchiveRepository(databasePath: ':memory:');
    addTearDown(repository.close);

    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pumpWidget(PersonEventAtlasApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('cascades Chinese locations through district', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: EventEditor(people: seedArchive.people)),
    );
    await tester.pumpAndSettle();

    expect(find.text('省级地区 *'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('country-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中国').last);
    await tester.pumpAndSettle();

    expect(find.text('省级地区 *'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('province-null')));
    await tester.tap(find.byKey(const ValueKey('province-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('福建省').last);
    await tester.pumpAndSettle();

    expect(find.text('城市 *'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('city-null')));
    await tester.tap(find.byKey(const ValueKey('city-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('厦门市').last);
    await tester.pumpAndSettle();

    expect(find.text('区/县 *'), findsOneWidget);
  });

  testWidgets('requires an event title before saving', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EventEditor(people: seedArchive.people)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();

    expect(find.text('请填写标题，并关联至少一位人物。'), findsOneWidget);
  });

  testWidgets('saves an event with an overseas location', (tester) async {
    EventItem? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<EventItem>(
                  context: context,
                  builder: (_) => EventEditor(people: seedArchive.people),
                );
              },
              child: const Text('打开编辑器'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '海外访谈');
    await tester.tap(find.byKey(const ValueKey('country-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(result?.title, '海外访谈');
    expect(result?.status, EventStatus.scheduled);
    expect(result?.place, '日本');
  });
}
