import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:person_event_atlas/app_settings.dart';
import 'package:person_event_atlas/app_update.dart';
import 'package:person_event_atlas/archive.dart';
import 'package:person_event_atlas/archive_repository.dart';
import 'package:person_event_atlas/event_location.dart';
import 'package:person_event_atlas/main.dart';

import 'test_data.dart';

void main() {
  test('keeps widget events in date order despite later edits', () {
    final event = seedArchive.events.first;
    final payload = widgetEventPayload(
      Archive(
        people: const [],
        events: [
          event.copyWith(
            title: 'older',
            start: '2025-01-01',
            updatedAt: DateTime(2030),
          ),
          event.copyWith(
            title: 'same-date-older-edit',
            start: '2025-03-01',
            updatedAt: DateTime(2025, 1, 1),
          ),
          event.copyWith(
            title: 'same-date-newer-edit',
            start: '2025-03-01',
            updatedAt: DateTime(2025, 1, 2),
          ),
          event.copyWith(
            title: 'undated',
            start: '',
            updatedAt: DateTime(2040),
            status: EventStatus.scheduled,
          ),
        ],
      ),
    );

    expect(payload.map((event) => event['title']), [
      'same-date-newer-edit',
      'same-date-older-edit',
      'older',
      'undated',
    ]);
  });

  testWidgets('uses a navigation rail on a wide window', (tester) async {
    final repository = ArchiveRepository(databasePath: ':memory:');
    addTearDown(repository.close);

    await tester.binding.setSurfaceSize(const Size(1100, 800));
    await tester.pumpWidget(PersonEventAtlasApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('事件时间线'), findsOneWidget);
    expect(find.text('标签管理'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('opens an event as a full-page detail on wide windows', (
    tester,
  ) async {
    final repository = ArchiveRepository(databasePath: ':memory:');
    addTearDown(repository.close);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await repository.savePerson(seedArchive.people.first);
    await repository.saveEvent(seedArchive.events.first);

    await tester.binding.setSurfaceSize(const Size(1100, 800));
    await tester.pumpWidget(PersonEventAtlasApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text(seedArchive.events.first.title));
    await tester.pumpAndSettle();

    expect(find.byType(ArchiveDetail), findsOneWidget);
    expect(
      find.byKey(const ValueKey('detail-expansion-animation')),
      findsOneWidget,
    );
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsNothing);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑事件'), findsOneWidget);
    expect(find.text('基本信息'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存修改'), findsOneWidget);

    await tester.tap(find.text('取消编辑'));
    await tester.pumpAndSettle();
    expect(find.text('事件详情'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('事件时间线'), findsOneWidget);
  });

  testWidgets('uses distinct semantic colors for event statuses', (
    tester,
  ) async {
    final events = EventStatus.values
        .map(
          (status) => seedArchive.events.first.copyWith(
            title: status.label,
            tags: const [],
            people: const [],
            status: status,
          ),
        )
        .toList();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineList(events: events, people: const [], onOpen: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chips = tester.widgetList<Chip>(find.byType(Chip)).toList();
    expect(chips, hasLength(EventStatus.values.length));
    expect(
      chips.map((chip) => chip.backgroundColor).toSet(),
      hasLength(EventStatus.values.length),
    );
  });

  testWidgets('opens settings with data management and theme controls', (
    tester,
  ) async {
    final repository = ArchiveRepository(databasePath: ':memory:');
    addTearDown(repository.close);

    await tester.binding.setSurfaceSize(const Size(1100, 800));
    await tester.pumpWidget(PersonEventAtlasApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('应用偏好'), findsOneWidget);
    expect(find.text('导入 JSON'), findsOneWidget);
    expect(find.text('导出 JSON'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.byType(SegmentedButton<AppThemeMode>), findsOneWidget);
    expect(find.byType(RadioListTile<AppThemeMode>), findsNothing);
    expect(find.text('森林绿'), findsOneWidget);
    expect(find.text('莓红 · 燕麦色'), findsOneWidget);
    expect(find.text('薄荷绿 · 炭灰色'), findsOneWidget);
    expect(find.text('宝蓝 · 明黄'), findsOneWidget);
    expect(find.text('亮橙 · 深青色'), findsOneWidget);
    expect(find.text('奶油白 · 草木绿'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('primary-berryRedOat')));
    await tester.pumpAndSettle();
    final paletteApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(paletteApp.theme?.colorScheme.primary, const Color(0xffb50031));
    expect(paletteApp.theme?.colorScheme.secondary, const Color(0xffdac9b1));
    expect(
      paletteApp.theme?.scaffoldBackgroundColor,
      isNot(const Color(0xfff7f7f1)),
    );
    expect(paletteApp.theme?.cardTheme.color, isNot(const Color(0xfffffefa)));

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme?.colorScheme.primary, const Color(0xffb50031));
    expect(
      app.darkTheme?.scaffoldBackgroundColor,
      isNot(const Color(0xff0f1012)),
    );
    expect(app.darkTheme?.cardTheme.color, isNot(const Color(0xff222529)));
  });

  testWidgets('changes the new event precision preference', (tester) async {
    AppSettings? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            settings: AppSettings.defaults,
            onChanged: (settings) async => changed = settings,
            onImport: () async {},
            onExport: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(MenuAnchor));
    await tester.pumpAndSettle();
    final menu = tester.widget<MenuAnchor>(find.byType(MenuAnchor));
    expect(menu.animated, isTrue);
    expect(menu.style?.alignment, AlignmentDirectional.bottomStart);
    expect(menu.style?.shape?.resolve({}), isA<RoundedRectangleBorder>());
    expect(
      tester.getTopLeft(find.text('年份').last).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(InputDecorator)).dy,
      ),
    );
    await tester.tap(find.text('月份').last);
    await tester.pumpAndSettle();

    expect(changed?.defaultPrecision, Precision.month);
  });

  testWidgets('checks GitHub releases from settings', (tester) async {
    final release = AppUpdateRelease(
      version: '0.1.5',
      tagName: 'v0.1.5',
      htmlUrl: Uri.parse(
        'https://github.com/duochifan2003/Thing/releases/tag/v0.1.5',
      ),
      notes: '修复更新功能。',
      assets: [
        AppUpdateAsset(
          name: 'Thing-macOS.dmg',
          downloadUrl: Uri.parse(
            'https://github.com/duochifan2003/Thing/releases/download/v0.1.5/Thing-macOS.dmg',
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            settings: AppSettings.defaults,
            onChanged: (_) async {},
            onImport: () async {},
            onExport: () async {},
            onCheckForUpdates: () async => release,
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '检查更新'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 v0.1.5，可以下载并安装。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '下载并安装'), findsOneWidget);
  });

  testWidgets('applies precision preference only to new event editors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventEditor(
            people: seedArchive.people,
            defaultPrecision: Precision.month,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editorMenus = tester.widgetList<MenuAnchor>(find.byType(MenuAnchor));
    expect(editorMenus, isNotEmpty);
    expect(editorMenus.every((menu) => menu.animated), isTrue);
    expect(find.text(Precision.month.label), findsOneWidget);
    expect(find.byType(Divider), findsNothing);

    final existing = seedArchive.events.first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventEditor(
            key: const ValueKey('existing-event'),
            initial: existing,
            people: seedArchive.people,
            defaultPrecision: Precision.range,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(existing.precision.label), findsOneWidget);
  });

  testWidgets('uses an animated anchored menu for detail actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArchiveDetail(
            event: seedArchive.events.first.copyWith(
              people: const <PersonLink>[],
              previousEventIds: const <String>[],
            ),
            archive: seedArchive,
            onClose: () {},
            onPerson: (_) {},
            onEvent: (_) {},
            onEditPerson: (_) {},
            onStartEventEdit: () {},
            onCancelEventEdit: () {},
            onSaveEvent: (_) async {},
            onDeletePerson: (_) {},
            onDeleteEvent: (_) {},
            onCancelEvent: (_) {},
            onTransitionEvent: (_, _) {},
            onPostponeEvent: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final menu = tester.widget<MenuAnchor>(find.byType(MenuAnchor));
    expect(menu.animated, isTrue);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsOneWidget);
  });

  testWidgets('edits a person directly from the people grid', (tester) async {
    Person? edited;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PeopleList(
            people: seedArchive.people,
            events: seedArchive.events,
            onOpen: (_) {},
            onEdit: (person) => edited = person,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('直接编辑').first);

    expect(edited?.id, seedArchive.people.first.id);
  });

  testWidgets('adds a person tag from the tag page', (tester) async {
    List<String>? saved;
    EntityType? savedType;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomTagsPage(
            personTags: const [],
            eventTags: const [],
            personCounts: const {},
            eventCounts: const {},
            onChanged: (type, tags) async {
              savedType = type;
              saved = tags;
            },
            onDelete: (_, _) async {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '长期项目');
    await tester.tap(find.widgetWithText(FilledButton, '添加').first);
    await tester.pumpAndSettle();

    expect(saved, ['长期项目']);
    expect(savedType, EntityType.person);
  });

  testWidgets('separates person and event tags on the tag page', (
    tester,
  ) async {
    EntityType? deletedType;
    String? deleted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomTagsPage(
            personTags: const ['人物标签'],
            eventTags: const ['事件标签'],
            personCounts: const {'人物标签': 2},
            eventCounts: const {'事件标签': 3},
            onChanged: (_, _) async {},
            onDelete: (type, tag) async {
              deletedType = type;
              deleted = tag;
            },
          ),
        ),
      ),
    );

    expect(find.text('预设标签'), findsNothing);
    expect(find.text('人物标签'), findsOneWidget);
    expect(find.text('事件标签'), findsOneWidget);
    expect(find.text('#人物标签'), findsOneWidget);
    expect(find.text('#事件标签'), findsOneWidget);
    expect(find.text('2 个人物'), findsOneWidget);
    expect(find.text('3 个事件'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(deletedType, EntityType.event);
    expect(deleted, '事件标签');
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
    expect(find.text('国家/地区 *'), findsOneWidget);
    expect(find.text('请选择'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('国家/地区 *')).dy,
      lessThan(tester.getTopLeft(find.text('请选择')).dy),
    );
    await tester.tap(find.byKey(const ValueKey('country-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中国').last);
    await tester.pumpAndSettle();

    expect(find.text('省级地区 *'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('province-null')));
    await tester.tap(find.byKey(const ValueKey('province-null')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('福建省').last);
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
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('请填写标题，并关联至少一位人物。'), findsOneWidget);
  });

  testWidgets('saves an event with an overseas location', (tester) async {
    EventItem? result;
    await tester.runAsync(() => WorldRegions.load());
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
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(result?.title, '海外访谈');
    expect(result?.status, EventStatus.scheduled);
    expect(result?.place, '日本');
  });

  testWidgets('shows overseas state and city selectors', (tester) async {
    await tester.runAsync(() => WorldRegions.load());
    await tester.pumpWidget(
      MaterialApp(home: EventEditor(people: seedArchive.people)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('country-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本').last);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('州/省级地区（可选）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('province-null')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tokyo').last);
    await tester.tap(find.text('Tokyo').last);
    await tester.pumpAndSettle();

    expect(find.text('城市（可选）'), findsOneWidget);
  });
}
