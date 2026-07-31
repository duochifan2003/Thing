import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'archive.dart';
import 'archive_repository.dart';
import 'event_location.dart';

abstract final class AtlasPalette {
  static const paper = Color(0xfff7f7f1);
  static const sidebar = Color(0xfff0f3ec);
  static const card = Color(0xfffffefa);
  static const ink = Color(0xff17211d);
  static const muted = Color(0xff758078);
  static const line = Color(0xffdfe5df);
  static const green = Color(0xff185c45);
  static const sage = Color(0xffdce7d6);
  static const navigationSelected = Color(0xffc5dbc0);
  static const interactiveHover = Color(0x1f185c45);
  static const interactiveSplash = Color(0x33185c45);
  static const accent = Color(0xffdd704c);
}

Color _eventStatusColor(EventStatus status) => switch (status) {
  EventStatus.scheduled => const Color(0xffffeee7),
  EventStatus.active => const Color(0xffe4efff),
  EventStatus.completed => const Color(0xffe8f2e5),
  EventStatus.cancelled => const Color(0xffeeeeee),
};

Color _eventStatusTextColor(EventStatus status) => switch (status) {
  EventStatus.scheduled => AtlasPalette.accent,
  EventStatus.active => const Color(0xff245b91),
  EventStatus.completed => const Color(0xff41614f),
  EventStatus.cancelled => AtlasPalette.muted,
};

String _formatLocalDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? _parseLocalDate(String value) {
  if (value.length != 10) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null || _formatLocalDate(parsed) != value) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

Widget _detailTransition(Widget child, Animation<double> animation) {
  final slide = Tween<Offset>(
    begin: const Offset(0.06, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
  return FadeTransition(
    opacity: animation,
    child: SlideTransition(position: slide, child: child),
  );
}

class _EditorDialog extends StatelessWidget {
  const _EditorDialog({
    required this.title,
    required this.content,
    required this.actions,
    required this.contentWidth,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final double contentWidth;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final horizontalInset = size.width < 720 ? 20.0 : 40.0;
    final dialogWidth = math.min(
      contentWidth,
      math.max(0.0, size.width - horizontalInset * 2),
    );
    final dialogHeight = math.max(240.0, size.height - 96);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: 48,
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.titleLarge,
                  child: title,
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                  children: [content],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: actions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _widgetChannel = MethodChannel('local.munch.eventatlas/widget');

Future<void> _updateWidget(Archive archive) async {
  if (!Platform.isMacOS) return;
  final events = [...archive.events]
    ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  try {
    await _widgetChannel.invokeMethod<void>('update', {
      'events': events
          .take(3)
          .map(
            (event) => {
              'id': event.id,
              'title': event.title,
              'precision': event.precision.name,
              'start': event.start,
              'end': event.end,
              'place': event.place,
            },
          )
          .toList(),
    });
  } on PlatformException {
    // Running outside the macOS app has no WidgetKit channel.
  } on MissingPluginException {
    // Running outside the macOS app has no WidgetKit channel.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PersonEventAtlasApp());
}

class PersonEventAtlasApp extends StatelessWidget {
  const PersonEventAtlasApp({super.key, this.repository});

  final ArchiveRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '事件录',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        scaffoldBackgroundColor: AtlasPalette.paper,
        colorScheme: const ColorScheme.light(
          primary: AtlasPalette.green,
          secondary: AtlasPalette.accent,
          surface: AtlasPalette.card,
          onSurface: AtlasPalette.ink,
          outline: AtlasPalette.line,
        ),
        cardTheme: const CardThemeData(
          color: AtlasPalette.card,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: AtlasPalette.line),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: AtlasPalette.card,
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: AtlasPalette.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: AtlasPalette.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: AtlasPalette.green, width: 1.5),
          ),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: AtlasPalette.sidebar,
          selectedIconTheme: IconThemeData(color: AtlasPalette.green),
          selectedLabelTextStyle: TextStyle(
            color: AtlasPalette.green,
            fontWeight: FontWeight.w700,
          ),
          indicatorColor: AtlasPalette.navigationSelected,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          useIndicator: true,
          unselectedIconTheme: IconThemeData(color: Color(0xff536159)),
          unselectedLabelTextStyle: TextStyle(color: Color(0xff536159)),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: AtlasPalette.sidebar,
          surfaceTintColor: Colors.transparent,
          indicatorColor: AtlasPalette.navigationSelected,
          overlayColor: WidgetStatePropertyAll<Color?>(
            AtlasPalette.interactiveHover,
          ),
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: Color(0xffedf3ea),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(5)),
          ),
          labelStyle: TextStyle(color: Color(0xff41614f), fontSize: 11),
          padding: EdgeInsets.symmetric(horizontal: 4),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AtlasPalette.green,
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AtlasPalette.green,
            side: const BorderSide(color: AtlasPalette.green),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: AtlasPalette.ink,
          displayColor: AtlasPalette.ink,
        ),
      ),
      home: ArchiveHome(repository: repository),
    );
  }
}

enum ArchiveView { timeline, people, tags }

class ArchiveFilters {
  const ArchiveFilters({
    this.personId,
    this.tag,
    this.role,
    this.from,
    this.to,
  });

  final String? personId;
  final String? tag;
  final Role? role;
  final String? from;
  final String? to;

  bool get active =>
      personId != null ||
      tag != null ||
      role != null ||
      from != null ||
      to != null;

  ArchiveFilters copyWith({
    String? personId,
    String? tag,
    Role? role,
    String? from,
    String? to,
    bool clearPerson = false,
    bool clearTag = false,
    bool clearRole = false,
    bool clearFrom = false,
    bool clearTo = false,
  }) => ArchiveFilters(
    personId: clearPerson ? null : personId ?? this.personId,
    tag: clearTag ? null : tag ?? this.tag,
    role: clearRole ? null : role ?? this.role,
    from: clearFrom ? null : from ?? this.from,
    to: clearTo ? null : to ?? this.to,
  );
}

class ArchiveHome extends StatefulWidget {
  const ArchiveHome({super.key, this.repository});

  final ArchiveRepository? repository;

  @override
  State<ArchiveHome> createState() => _ArchiveHomeState();
}

class _ArchiveHomeState extends State<ArchiveHome> {
  late final ArchiveRepository _repository =
      widget.repository ?? ArchiveRepository();
  Archive? _archive;
  ArchiveView _view = ArchiveView.timeline;
  ArchiveFilters _filters = const ArchiveFilters();
  String _query = '';
  String? _personId;
  String? _eventId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _repository.close();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final archive = await _repository.load();
      unawaited(_updateWidget(archive));
      if (mounted) {
        setState(() {
          _archive = archive;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开本地档案，请从备份恢复。');
    }
  }

  Future<void> _write(Future<void> Function() action) async {
    try {
      await action();
      await _reload();
    } on FormatException catch (error) {
      _notice(error.message.toString());
    } catch (_) {
      _notice('保存失败：资料尚未写入本机。');
    }
  }

  void _notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Person? get _selectedPerson =>
      _archive?.people.where((person) => person.id == _personId).firstOrNull;
  EventItem? get _selectedEvent =>
      _archive?.events.where((event) => event.id == _eventId).firstOrNull;

  void _selectPerson(String id) => setState(() {
    _personId = id;
    _eventId = null;
    _view = ArchiveView.people;
  });
  void _selectEvent(String id) => setState(() {
    _eventId = id;
    _personId = null;
    _view = ArchiveView.timeline;
  });
  void _clearSelection() => setState(() {
    _personId = null;
    _eventId = null;
  });

  Future<void> _editPerson([Person? initial]) async {
    final person = await showDialog<Person>(
      context: context,
      builder: (_) => PersonEditor(
        initial: initial,
        customTags: _archive == null ? const [] : _customTags(_archive!),
      ),
    );
    if (person == null) return;
    await _write(() => _repository.savePerson(person));
    if (mounted) _selectPerson(person.id);
  }

  Future<void> _editEvent([EventItem? initial]) async {
    final archive = _archive;
    if (archive == null) return;
    if (archive.people.isEmpty) {
      _notice('请先新建至少一位人物。');
      return;
    }
    final event = await showDialog<EventItem>(
      context: context,
      builder: (_) => EventEditor(
        initial: initial,
        people: archive.people,
        events: archive.events,
        customTags: _customTags(archive),
      ),
    );
    if (event == null) return;
    await _write(() => _repository.saveEvent(event));
    if (mounted) _selectEvent(event.id);
  }

  Future<void> _saveCustomTags(List<String> tags) async {
    await _write(() => _repository.saveCustomTags(tags));
  }

  Future<void> _deleteCustomTag(String tag) async {
    final archive = _archive;
    if (archive == null) return;
    final updated = archive.copyWith(
      customTags: archive.customTags.where((item) => item != tag).toList(),
      people: archive.people
          .map(
            (person) => person.copyWith(
              tags: person.tags.where((item) => item != tag).toList(),
            ),
          )
          .toList(),
      events: archive.events
          .map(
            (event) => event.copyWith(
              tags: event.tags.where((item) => item != tag).toList(),
            ),
          )
          .toList(),
    );
    await _write(() => _repository.replace(updated));
  }

  Future<void> _deletePerson(Person person) async {
    if (!await _confirm('删除人物', '确定删除「${person.name}」吗？此操作不可撤销。')) return;
    final deleted = await _repository.deletePerson(person.id);
    if (!deleted) {
      _notice('该人物仍关联事件，请先删除或编辑相关事件。');
      return;
    }
    _clearSelection();
    await _reload();
  }

  Future<void> _cancelEvent(EventItem event) async {
    if (!await _confirm(
      '取消事件',
      '确定取消「${event.title}」吗？取消后仍会保留记录。',
      confirmLabel: '取消事件',
    )) {
      return;
    }
    await _write(
      () => _repository.transitionEvent(event.id, EventStatus.cancelled),
    );
  }

  Future<void> _transitionEvent(EventItem event, EventStatus status) async {
    await _write(() => _repository.transitionEvent(event.id, status));
  }

  Future<void> _postponeEvent(EventItem event) async {
    final initialDate = _parseLocalDate(event.start) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: event.start.isEmpty ? '设置日期' : '延期至',
      cancelText: '取消',
      confirmText: '保存',
    );
    if (picked == null) return;
    final date = _formatLocalDate(picked);
    await _write(
      () => _repository.saveEvent(
        event.copyWith(
          precision: Precision.day,
          start: date,
          clearEnd: true,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> _deleteEvent(EventItem event) async {
    if (!await _confirm('永久删除事件', '确定永久删除「${event.title}」吗？此操作不可撤销。')) return;
    await _write(() => _repository.deleteEvent(event.id));
    _clearSelection();
  }

  Future<bool> _confirm(
    String title,
    String body, {
    String confirmLabel = '删除',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _importArchive() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON 档案', extensions: ['json']),
      ],
    );
    if (file == null) return;
    try {
      final imported = Archive.decode(await file.readAsString());
      final preview = await _repository.preview(imported);
      if (!mounted) return;
      final replace = await showDialog<bool>(
        context: context,
        builder: (_) => ImportPreviewDialog(preview: preview),
      );
      if (replace == true) {
        await _write(() => _repository.replace(imported));
        _clearSelection();
      }
    } on FormatException catch (error) {
      _notice(error.message.toString());
    } catch (_) {
      _notice('无法读取该档案文件。');
    }
  }

  Future<void> _exportArchive() async {
    final archive = _archive;
    if (archive == null) return;
    final name =
        '人物事件档案-${DateTime.now().toIso8601String().substring(0, 10)}.json';
    final location = await getSaveLocation(suggestedName: name);
    if (location == null) return;
    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(archive.encode())),
      mimeType: 'application/json',
      name: name,
    );
    await file.saveTo(location.path);
    if (mounted) _notice('档案已导出。');
  }

  @override
  Widget build(BuildContext context) {
    final archive = _archive;
    if (archive == null) {
      return Scaffold(body: Center(child: Text(_error ?? '正在打开本地档案…')));
    }
    final people = _filteredPeople(archive);
    final events = _filteredEvents(archive);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final tagsView = _view == ArchiveView.tags;
        final selected = _selectedPerson ?? _selectedEvent;
        final list = switch (_view) {
          ArchiveView.timeline => TimelineList(
            events: events,
            people: archive.people,
            onOpen: _selectEvent,
          ),
          ArchiveView.people => PeopleList(
            people: people,
            events: archive.events,
            onOpen: _selectPerson,
          ),
          ArchiveView.tags => CustomTagsPage(
            customTags: _customTags(archive),
            eventCounts: {
              for (final tag in _customTags(archive))
                tag: archive.events
                    .where((event) => event.tags.contains(tag))
                    .length,
            },
            onChanged: _saveCustomTags,
            onDelete: _deleteCustomTag,
          ),
        };
        final workspace = Column(
          children: [
            _Header(
              view: _view,
              onImport: _importArchive,
              onExport: _exportArchive,
              showArchiveMenu: !desktop,
            ),
            if (!tagsView)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索人物、事件、地点或标签',
                  ),
                ),
              ),
            if (!tagsView)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: FilterBar(
                      archive: archive,
                      filters: _filters,
                      onChanged: (value) => setState(() => _filters = value),
                    ),
                  ),
                  if (desktop)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 16, 12),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: _view == ArchiveView.timeline
                            ? _editEvent
                            : _editPerson,
                        icon: const Icon(Icons.add),
                        label: Text(
                          _view == ArchiveView.timeline ? '新增事件' : '新增人物',
                        ),
                      ),
                    ),
                ],
              ),
            if (_view == ArchiveView.timeline && !tagsView)
              ReminderPanel(events: _dueEvents(archive), onOpen: _selectEvent),
            Expanded(
              child: desktop
                  ? Row(
                      children: [
                        Expanded(child: list),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.centerRight,
                          child: selected != null && !tagsView
                              ? AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  transitionBuilder: _detailTransition,
                                  child: SizedBox(
                                    key: ValueKey(
                                      'detail-${_eventId ?? _personId}',
                                    ),
                                    width: 390,
                                    child: ArchiveDetail(
                                      person: _selectedPerson,
                                      event: _selectedEvent,
                                      archive: archive,
                                      onClose: _clearSelection,
                                      onPerson: _selectPerson,
                                      onEvent: _selectEvent,
                                      onEditPerson: _editPerson,
                                      onEditEvent: _editEvent,
                                      onDeletePerson: _deletePerson,
                                      onDeleteEvent: _deleteEvent,
                                      onCancelEvent: _cancelEvent,
                                      onTransitionEvent: _transitionEvent,
                                      onPostponeEvent: _postponeEvent,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: _detailTransition,
                      child: selected != null && !tagsView
                          ? KeyedSubtree(
                              key: ValueKey('detail-${_eventId ?? _personId}'),
                              child: ArchiveDetail(
                                person: _selectedPerson,
                                event: _selectedEvent,
                                archive: archive,
                                onClose: _clearSelection,
                                onPerson: _selectPerson,
                                onEvent: _selectEvent,
                                onEditPerson: _editPerson,
                                onEditEvent: _editEvent,
                                onDeletePerson: _deletePerson,
                                onDeleteEvent: _deleteEvent,
                                onCancelEvent: _cancelEvent,
                                onTransitionEvent: _transitionEvent,
                                onPostponeEvent: _postponeEvent,
                              ),
                            )
                          : KeyedSubtree(
                              key: ValueKey('list-${_view.name}'),
                              child: list,
                            ),
                    ),
            ),
          ],
        );
        return Scaffold(
          body: SafeArea(
            child: desktop
                ? Row(
                    children: [
                      NavigationRail(
                        backgroundColor: AtlasPalette.sidebar,
                        extended: true,
                        minExtendedWidth: 264,
                        groupAlignment: -0.78,
                        selectedIndex: _view.index,
                        onDestinationSelected: (index) => setState(() {
                          _view = ArchiveView.values[index];
                          _personId = null;
                          _eventId = null;
                        }),
                        leading: const Padding(
                          padding: EdgeInsets.fromLTRB(12, 22, 12, 28),
                          child: _Brand(),
                        ),
                        trailing: SizedBox(
                          width: 228,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Divider(color: AtlasPalette.line),
                                const SizedBox(height: 14),
                                const Text(
                                  '你的资料只保存在此设备。\n导出文件可用于备份与迁移。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.6,
                                    color: AtlasPalette.muted,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton(
                                  onPressed: _exportArchive,
                                  child: const Text('导出 JSON'),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: _importArchive,
                                  child: const Text('导入资料'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.timeline_outlined),
                            selectedIcon: Icon(Icons.timeline),
                            label: Text('时间线'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.people_outline),
                            selectedIcon: Icon(Icons.people),
                            label: Text('人物目录'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.sell_outlined),
                            selectedIcon: Icon(Icons.sell),
                            label: Text('标签管理'),
                          ),
                        ],
                      ),
                      Expanded(child: workspace),
                    ],
                  )
                : workspace,
          ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: _view.index,
                  onDestinationSelected: (index) => setState(() {
                    _view = ArchiveView.values[index];
                    _personId = null;
                    _eventId = null;
                  }),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.timeline_outlined),
                      selectedIcon: Icon(Icons.timeline),
                      label: '时间线',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: '人物',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.sell_outlined),
                      selectedIcon: Icon(Icons.sell),
                      label: '标签',
                    ),
                  ],
                ),
          floatingActionButton: desktop || tagsView
              ? null
              : FloatingActionButton.extended(
                  onPressed: _view == ArchiveView.timeline
                      ? () => _editEvent()
                      : () => _editPerson(),
                  icon: const Icon(Icons.add),
                  label: Text(_view == ArchiveView.timeline ? '事件' : '人物'),
                ),
        );
      },
    );
  }

  List<EventItem> _dueEvents(Archive archive) {
    final today = _formatLocalDate(DateTime.now());
    return archive.events
        .where(
          (event) =>
              event.status == EventStatus.scheduled &&
              event.start.isNotEmpty &&
              event.start.compareTo(today) <= 0,
        )
        .toList()
      ..sort((left, right) => left.start.compareTo(right.start));
  }

  List<String> _customTags(Archive archive) {
    final tags = {
      ...archive.customTags,
      ...archive.people.expand((person) => person.tags),
      ...archive.events.expand((event) => event.tags),
    };
    return tags.toList()..sort();
  }

  List<EventItem> _filteredEvents(Archive archive) {
    final query = _query.trim().toLowerCase();
    final names = {for (final person in archive.people) person.id: person.name};
    return archive.events.where((event) {
      final contents = [
        event.title,
        event.place,
        event.description,
        ...event.tags,
        ...event.people.map((link) => names[link.personId] ?? ''),
      ].join(' ').toLowerCase();
      final last = event.end?.isNotEmpty == true ? event.end! : event.start;
      return (query.isEmpty || contents.contains(query)) &&
          (_filters.personId == null ||
              event.people.any((link) => link.personId == _filters.personId)) &&
          (_filters.tag == null || event.tags.contains(_filters.tag)) &&
          (_filters.role == null ||
              event.people.any((link) => link.role == _filters.role)) &&
          (_filters.from == null || last.compareTo(_filters.from!) >= 0) &&
          (_filters.to == null || event.start.compareTo(_filters.to!) <= 0);
    }).toList();
  }

  List<Person> _filteredPeople(Archive archive) {
    final query = _query.trim().toLowerCase();
    return archive.people.where((person) {
      final related = archive.events.where(
        (event) => event.people.any((link) => link.personId == person.id),
      );
      final rangeMatches = related.any((event) {
        final last = event.end?.isNotEmpty == true ? event.end! : event.start;
        return (_filters.from == null || last.compareTo(_filters.from!) >= 0) &&
            (_filters.to == null || event.start.compareTo(_filters.to!) <= 0);
      });
      return (query.isEmpty ||
              [
                person.name,
                person.bio,
                ...person.tags,
                person.notes,
              ].join(' ').toLowerCase().contains(query)) &&
          (_filters.personId == null || person.id == _filters.personId) &&
          (_filters.tag == null || person.tags.contains(_filters.tag)) &&
          (_filters.role == null ||
              related.any(
                (event) => event.people.any(
                  (link) =>
                      link.personId == person.id && link.role == _filters.role,
                ),
              )) &&
          ((_filters.from == null && _filters.to == null) || rangeMatches);
    }).toList();
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset('assets/logo.png', width: 34, height: 34),
      const SizedBox(width: 10),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('事件录', style: TextStyle(fontWeight: FontWeight.w700)),
          Text(
            'PERSON · EVENT ATLAS',
            style: TextStyle(fontSize: 9, color: AtlasPalette.muted),
          ),
        ],
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.view,
    required this.onImport,
    required this.onExport,
    required this.showArchiveMenu,
  });
  final ArchiveView view;
  final Future<void> Function() onImport;
  final Future<void> Function() onExport;
  final bool showArchiveMenu;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PERSON · EVENT ATLAS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AtlasPalette.green,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(switch (view) {
                ArchiveView.timeline => '事件时间线',
                ArchiveView.people => '人物目录',
                ArchiveView.tags => '标签管理',
              }, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
        if (showArchiveMenu)
          PopupMenuButton<String>(
            tooltip: '档案操作',
            onSelected: (value) {
              if (value == 'import') onImport();
              if (value == 'export') onExport();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('导入 JSON')),
              PopupMenuItem(value: 'export', child: Text('导出 JSON')),
            ],
          ),
        if (showArchiveMenu) const SizedBox(width: 4),
      ],
    ),
  );
}

class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.archive,
    required this.filters,
    required this.onChanged,
  });
  final Archive archive;
  final ArchiveFilters filters;
  final ValueChanged<ArchiveFilters> onChanged;
  @override
  Widget build(BuildContext context) {
    final tags = {
      ...archive.people.expand((person) => person.tags),
      ...archive.events.expand((event) => event.tags),
    }.toList()..sort();
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                '筛选条件',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: AtlasPalette.muted),
              ),
            ),
            _filterMenu<String?>(
              context,
              '关联人物',
              filters.personId,
              [
                const DropdownMenuItem(value: null, child: Text('关联人物：全部')),
                ...archive.people.map(
                  (person) => DropdownMenuItem(
                    value: person.id,
                    child: Text('关联人物：${person.name}'),
                  ),
                ),
              ],
              (value) => onChanged(
                filters.copyWith(personId: value, clearPerson: value == null),
              ),
            ),
            _filterMenu<String?>(
              context,
              '事件标签',
              filters.tag,
              [
                const DropdownMenuItem(value: null, child: Text('事件标签：全部')),
                ...tags.map(
                  (tag) =>
                      DropdownMenuItem(value: tag, child: Text('事件标签：#$tag')),
                ),
              ],
              (value) => onChanged(
                filters.copyWith(tag: value, clearTag: value == null),
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: () async {
                final range = await showDialog<_DateRange>(
                  context: context,
                  builder: (_) =>
                      DateRangeDialog(from: filters.from, to: filters.to),
                );
                if (range != null) {
                  onChanged(
                    filters.copyWith(
                      from: range.from,
                      to: range.to,
                      clearFrom: range.from == null,
                      clearTo: range.to == null,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(
                filters.from == null && filters.to == null
                    ? '事件日期：不限'
                    : '事件日期：${filters.from ?? '最早'} 至 ${filters.to ?? '现在'}',
              ),
            ),
            const SizedBox(width: 8),
            if (filters.active)
              TextButton(
                onPressed: () => onChanged(const ArchiveFilters()),
                child: const Text('清除筛选'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filterMenu<T>(
    BuildContext context,
    String label,
    T value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: value == null ? AtlasPalette.card : AtlasPalette.sage,
        border: Border.all(
          color: value == null ? AtlasPalette.line : AtlasPalette.green,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text('$label：全部'),
          isDense: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          focusColor: Colors.transparent,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          dropdownColor: AtlasPalette.card,
          elevation: 6,
          items: items,
          onChanged: (next) {
            if (next != null || T.toString().contains('null')) {
              onChanged(next as T);
            }
          },
        ),
      ),
    ),
  );
}

class _DateRange {
  const _DateRange({this.from, this.to});
  final String? from;
  final String? to;
}

class DateRangeDialog extends StatefulWidget {
  const DateRangeDialog({super.key, this.from, this.to});
  final String? from;
  final String? to;
  @override
  State<DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<DateRangeDialog> {
  late final _from = TextEditingController(text: widget.from);
  late final _to = TextEditingController(text: widget.to);
  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('筛选事件日期'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _from,
          readOnly: true,
          onTap: () => _pickDate(_from),
          decoration: InputDecoration(
            labelText: '开始日期',
            hintText: '点击选择日期',
            suffixIcon: _from.text.isEmpty
                ? const Icon(Icons.calendar_today, size: 18)
                : IconButton(
                    onPressed: () => setState(_from.clear),
                    icon: const Icon(Icons.clear),
                    tooltip: '清空日期',
                  ),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _to,
          readOnly: true,
          onTap: () => _pickDate(_to),
          decoration: InputDecoration(
            labelText: '结束日期',
            hintText: '点击选择日期',
            suffixIcon: _to.text.isEmpty
                ? const Icon(Icons.calendar_today, size: 18)
                : IconButton(
                    onPressed: () => setState(_to.clear),
                    icon: const Icon(Icons.clear),
                    tooltip: '清空日期',
                  ),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, const _DateRange()),
        child: const Text('清除'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _apply, child: const Text('应用')),
    ],
  );

  Future<void> _pickDate(TextEditingController controller) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _parseLocalDate(controller.text) ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: controller == _from ? '选择开始日期' : '选择结束日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) return;
    setState(() => controller.text = _formatLocalDate(picked));
  }

  void _apply() {
    final from = _from.text.trim().isEmpty ? null : _from.text.trim();
    final to = _to.text.trim().isEmpty ? null : _to.text.trim();
    if (from != null && to != null && from.compareTo(to) > 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结束时间不能早于开始时间。')));
      return;
    }
    Navigator.pop(context, _DateRange(from: from, to: to));
  }
}

class ReminderPanel extends StatelessWidget {
  const ReminderPanel({super.key, required this.events, required this.onOpen});

  final List<EventItem> events;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final today = _formatLocalDate(DateTime.now());
    return Card(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined, size: 18),
                const SizedBox(width: 8),
                Text('待办提醒', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            ...events.map(
              (event) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                mouseCursor: SystemMouseCursors.click,
                hoverColor: AtlasPalette.interactiveHover,
                splashColor: AtlasPalette.interactiveSplash,
                onTap: () => onOpen(event.id),
                title: Text(event.title),
                subtitle: Text(
                  event.start == today ? '今天' : '逾期 · ${event.dateLabel}',
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TimelineList extends StatelessWidget {
  const TimelineList({
    super.key,
    required this.events,
    required this.people,
    required this.onOpen,
  });
  final List<EventItem> events;
  final List<Person> people;
  final ValueChanged<String> onOpen;
  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const EmptyState(title: '没有匹配的事件', text: '调整筛选条件，或新建第一条事件记录。');
    }
    final names = {for (final person in people) person.id: person.name};
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final event = events[index];
        final links = _orderedPeople(event.people);
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 116,
                child: Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: Text(
                    event.dateLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                      color: AtlasPalette.muted,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 26,
                child: Stack(
                  children: [
                    if (index < events.length - 1)
                      Positioned(
                        left: 9,
                        top: 32,
                        bottom: -10,
                        child: Container(width: 1, color: AtlasPalette.line),
                      ),
                    Positioned(
                      top: 24,
                      left: 4,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AtlasPalette.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    mouseCursor: SystemMouseCursors.click,
                    hoverColor: AtlasPalette.interactiveHover,
                    splashColor: AtlasPalette.interactiveSplash,
                    onTap: () => onOpen(event.id),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.title,
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                                if (event.place.isNotEmpty)
                                  Text(
                                    event.place,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AtlasPalette.muted,
                                    ),
                                  ),
                                if (event.description.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 7),
                                    child: Text(
                                      event.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    Chip(
                                      backgroundColor: _eventStatusColor(
                                        event.status,
                                      ),
                                      label: Text(
                                        event.status.label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _eventStatusTextColor(
                                            event.status,
                                          ),
                                        ),
                                      ),
                                    ),
                                    ...event.tags.map(
                                      (tag) => Chip(
                                        label: Text(
                                          '#$tag',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    ),
                                    ...links.map(
                                      (link) => Chip(
                                        backgroundColor: const Color(
                                          0xffffe9e1,
                                        ),
                                        label: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.person_outline,
                                              size: 15,
                                              color: AtlasPalette.accent,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                '${names[link.personId] ?? '未知人物'} · ${link.role.label}',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: AtlasPalette.accent,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_outward),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

List<PersonLink> _orderedPeople(Iterable<PersonLink> people) =>
    [...people]..sort(
      (left, right) => (left.role == Role.organizer ? 0 : 1).compareTo(
        right.role == Role.organizer ? 0 : 1,
      ),
    );

class PeopleList extends StatelessWidget {
  const PeopleList({
    super.key,
    required this.people,
    required this.events,
    required this.onOpen,
  });
  final List<Person> people;
  final List<EventItem> events;
  final ValueChanged<String> onOpen;
  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return const EmptyState(title: '没有匹配的人物', text: '调整搜索条件，或新建人物档案。');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: people.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final person = people[index];
        final count = events
            .where(
              (event) => event.people.any((link) => link.personId == person.id),
            )
            .length;
        return Card(
          child: ListTile(
            mouseCursor: SystemMouseCursors.click,
            hoverColor: AtlasPalette.interactiveHover,
            splashColor: AtlasPalette.interactiveSplash,
            onTap: () => onOpen(person.id),
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: AtlasPalette.sage,
              child: Text(person.name.characters.first),
            ),
            title: Text(person.name),
            subtitle: Text(
              '${person.bio.isEmpty ? '尚未添加简介' : person.bio}\n关联 $count 个事件',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }
}

class ArchiveDetail extends StatelessWidget {
  const ArchiveDetail({
    super.key,
    this.person,
    this.event,
    required this.archive,
    required this.onClose,
    required this.onPerson,
    required this.onEvent,
    required this.onEditPerson,
    required this.onEditEvent,
    required this.onDeletePerson,
    required this.onDeleteEvent,
    required this.onCancelEvent,
    required this.onTransitionEvent,
    required this.onPostponeEvent,
  });
  final Person? person;
  final EventItem? event;
  final Archive archive;
  final VoidCallback onClose;
  final ValueChanged<String> onPerson;
  final ValueChanged<String> onEvent;
  final ValueChanged<Person> onEditPerson;
  final ValueChanged<EventItem> onEditEvent;
  final ValueChanged<Person> onDeletePerson;
  final ValueChanged<EventItem> onDeleteEvent;
  final ValueChanged<EventItem> onCancelEvent;
  final void Function(EventItem, EventStatus) onTransitionEvent;
  final ValueChanged<EventItem> onPostponeEvent;
  @override
  Widget build(BuildContext context) {
    final item = person ?? event;
    if (item == null) return const SizedBox.shrink();
    final names = {for (final item in archive.people) item.id: item};
    final related = person == null
        ? const <EventItem>[]
        : archive.events
              .where(
                (item) =>
                    item.people.any((link) => link.personId == person!.id),
              )
              .toList();
    return Container(
      decoration: const BoxDecoration(
        color: AtlasPalette.card,
        border: Border(left: BorderSide(color: AtlasPalette.line)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'edit') {
                    person != null
                        ? onEditPerson(person!)
                        : onEditEvent(event!);
                  }
                  if (person != null && action == 'delete') {
                    onDeletePerson(person!);
                  }
                  if (event != null) {
                    if (action == 'cancel') onCancelEvent(event!);
                    if (action == 'postpone') onPostponeEvent(event!);
                    if (action == 'start') {
                      onTransitionEvent(event!, EventStatus.active);
                    }
                    if (action == 'complete') {
                      onTransitionEvent(event!, EventStatus.completed);
                    }
                    if (action == 'permanent-delete') {
                      onDeleteEvent(event!);
                    }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  if (event != null && event!.status == EventStatus.scheduled)
                    PopupMenuItem(
                      value: 'postpone',
                      child: Text(event!.start.isEmpty ? '设置日期' : '延期'),
                    ),
                  if (event != null && event!.status == EventStatus.scheduled)
                    const PopupMenuItem(value: 'start', child: Text('开始')),
                  if (event != null && event!.status == EventStatus.active)
                    const PopupMenuItem(value: 'complete', child: Text('结束')),
                  if (event != null &&
                      (event!.status == EventStatus.scheduled ||
                          event!.status == EventStatus.active))
                    const PopupMenuItem(value: 'cancel', child: Text('取消事件')),
                  if (person != null)
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  if (event != null)
                    const PopupMenuItem(
                      value: 'permanent-delete',
                      child: Text('永久删除'),
                    ),
                ],
              ),
            ],
          ),
          if (person != null)
            CircleAvatar(
              radius: 28,
              backgroundColor: AtlasPalette.sage,
              child: Text(
                person!.name.characters.first,
                style: const TextStyle(fontSize: 22),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            person != null ? '人物档案' : event!.dateLabel,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 4),
          Text(
            person?.name ?? event!.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if ((person?.bio ?? event?.description ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(person?.bio ?? event!.description),
            ),
          const SizedBox(height: 24),
          if (event != null) ...[
            Chip(
              backgroundColor: _eventStatusColor(event!.status),
              label: Text(
                event!.status.label,
                style: TextStyle(color: _eventStatusTextColor(event!.status)),
              ),
            ),
            const SizedBox(height: 12),
            DetailSection(
              title: '事件信息',
              values: {'时间': event!.dateLabel, '地点': event!.place},
            ),
            const SizedBox(height: 20),
            Text('关联人物', style: Theme.of(context).textTheme.titleMedium),
            ..._orderedPeople(event!.people).map(
              (link) => ListTile(
                contentPadding: EdgeInsets.zero,
                mouseCursor: SystemMouseCursors.click,
                hoverColor: AtlasPalette.interactiveHover,
                splashColor: AtlasPalette.interactiveSplash,
                onTap: () => onPerson(link.personId),
                title: Text(names[link.personId]?.name ?? '未知人物'),
                trailing: Text(link.role.label),
              ),
            ),
            if (event!.previousEventIds.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('前序事件', style: Theme.of(context).textTheme.titleMedium),
              ...event!.previousEventIds.map((id) {
                final previous = archive.events
                    .where((item) => item.id == id)
                    .firstOrNull;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  mouseCursor: previous == null
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  hoverColor: AtlasPalette.interactiveHover,
                  splashColor: AtlasPalette.interactiveSplash,
                  onTap: previous == null ? null : () => onEvent(id),
                  title: Text(previous?.title ?? '未知事件'),
                  subtitle: Text(previous?.dateLabel ?? '关联资料缺失'),
                  trailing: const Icon(Icons.chevron_right),
                );
              }),
            ],
          ],
          if (person != null) ...[
            DetailSection(
              title: '资料',
              values: {
                '标签': person!.tags.map((tag) => '#$tag').join('  '),
                '备注': person!.notes,
                '来源': person!.sources.join('；'),
              },
            ),
            const SizedBox(height: 20),
            Text('相关事件', style: Theme.of(context).textTheme.titleMedium),
            ...related.map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                mouseCursor: SystemMouseCursors.click,
                hoverColor: AtlasPalette.interactiveHover,
                splashColor: AtlasPalette.interactiveSplash,
                onTap: () => onEvent(item.id),
                title: Text(item.title),
                subtitle: Text(item.dateLabel),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.title, required this.values});
  final String title;
  final Map<String, String> values;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      ...values.entries
          .where((entry) => entry.value.isNotEmpty)
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      entry.key,
                      style: const TextStyle(color: AtlasPalette.muted),
                    ),
                  ),
                  Expanded(child: Text(entry.value)),
                ],
              ),
            ),
          ),
    ],
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.text});
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 28),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class ImportPreviewDialog extends StatelessWidget {
  const ImportPreviewDialog({super.key, required this.preview});
  final ImportPreview preview;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('准备导入档案包'),
    content: Text(
      '将检测到 ${preview.add} 条新记录，${preview.duplicate} 条相同记录，以及 ${preview.conflict} 条同 ID 冲突记录。\n\n确认后会用导入档案完整替换当前本地资料。',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('确认替换'),
      ),
    ],
  );
}

class CustomTagsPage extends StatefulWidget {
  const CustomTagsPage({
    super.key,
    required this.customTags,
    required this.eventCounts,
    required this.onChanged,
    required this.onDelete,
  });

  final List<String> customTags;
  final Map<String, int> eventCounts;
  final Future<void> Function(List<String>) onChanged;
  final Future<void> Function(String) onDelete;

  @override
  State<CustomTagsPage> createState() => _CustomTagsPageState();
}

class _CustomTagsPageState extends State<CustomTagsPage> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final tag = _controller.text.trim();
    if (tag.isEmpty) return;
    final tags = {...widget.customTags, tag}.toList()..sort();
    await _save(tags);
    if (mounted) _controller.clear();
  }

  Future<void> _remove(String tag) async {
    if (_saving) return;
    final eventCount = widget.eventCounts[tag] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('「#$tag」关联 $eventCount 个事件，删除后会同时从事件和人物中移除。是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.onDelete(tag);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save(List<String> tags) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onChanged(tags);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('自定义标签', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              '在这里维护所有可复用的自定义标签，事件和人物编辑时直接选择。',
              style: TextStyle(color: AtlasPalette.muted),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_saving,
                    onSubmitted: (_) => _add(),
                    decoration: const InputDecoration(
                      labelText: '新标签',
                      hintText: '例如：厦门、长期项目',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _saving ? null : _add,
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text('我的标签', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            if (widget.customTags.isEmpty)
              const Text(
                '还没有自定义标签。',
                style: TextStyle(color: AtlasPalette.muted),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: widget.customTags
                    .map(
                      (tag) => SizedBox(
                        width: 260,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '#$tag',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AtlasPalette.green,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '关联 ${widget.eventCounts[tag] ?? 0} 个事件',
                                        style: const TextStyle(
                                          color: AtlasPalette.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: '删除标签',
                                  onPressed: _saving
                                      ? null
                                      : () => _remove(tag),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    ],
  );
}

class PersonEditor extends StatefulWidget {
  const PersonEditor({super.key, this.initial, this.customTags = const []});
  final Person? initial;
  final List<String> customTags;
  @override
  State<PersonEditor> createState() => _PersonEditorState();
}

class _PersonEditorState extends State<PersonEditor> {
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _bio = TextEditingController(text: widget.initial?.bio);
  late final _tags = TextEditingController(
    text: widget.initial?.tags.join('，'),
  );
  late final _notes = TextEditingController(text: widget.initial?.notes);
  late final _sources = TextEditingController(
    text: widget.initial?.sources.join('，'),
  );
  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _tags.dispose();
    _notes.dispose();
    _sources.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _EditorDialog(
    title: Text(widget.initial == null ? '新增人物' : '编辑人物'),
    contentWidth: 400,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: '姓名 *'),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _bio,
          decoration: const InputDecoration(labelText: '简介'),
        ),
        const SizedBox(height: 28),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('标签', style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _availableTags
                .map(
                  (tag) => FilterChip(
                    label: Text(tag),
                    selected: _split(_tags.text).contains(tag),
                    onSelected: (selected) => _toggleTag(tag, selected),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _notes,
          maxLines: 2,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _sources,
          decoration: const InputDecoration(labelText: '来源'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );

  List<String> get _availableTags {
    final tags = {...widget.customTags, ..._split(_tags.text)}.toList()..sort();
    return tags;
  }

  void _toggleTag(String tag, bool selected) {
    final tags = _split(_tags.text).toSet();
    if (selected) {
      tags.add(tag);
    } else {
      tags.remove(tag);
    }
    setState(() => _tags.text = tags.join('，'));
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final now = DateTime.now();
    Navigator.pop(
      context,
      Person(
        id: widget.initial?.id ?? 'p-${now.microsecondsSinceEpoch}',
        name: name,
        bio: _bio.text.trim(),
        tags: _split(_tags.text),
        notes: _notes.text.trim(),
        sources: _split(_sources.text),
        createdAt: widget.initial?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }
}

class EventEditor extends StatefulWidget {
  const EventEditor({
    super.key,
    this.initial,
    required this.people,
    this.events = const [],
    this.customTags = const [],
  });
  final EventItem? initial;
  final List<Person> people;
  final List<EventItem> events;
  final List<String> customTags;
  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  late final _id =
      widget.initial?.id ?? 'e-${DateTime.now().microsecondsSinceEpoch}';
  late final _createdAt = widget.initial?.createdAt ?? DateTime.now();
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _start = TextEditingController(text: widget.initial?.start);
  late final _end = TextEditingController(text: widget.initial?.end);
  late final _initialLocation = EventLocation.fromStored(
    widget.initial?.place ?? '',
    chinaRegions: chinaRegions,
  );
  late String? _country = _initialLocation.country;
  late String? _province = _initialLocation.province;
  late String? _city = _initialLocation.city;
  late String? _district = _initialLocation.district;
  late final _placeDetail = TextEditingController(
    text: _initialLocation.detail,
  );
  late final _description = TextEditingController(
    text: widget.initial?.description,
  );
  late final _tags = TextEditingController(
    text: widget.initial?.tags.join('，'),
  );
  late Precision _precision = widget.initial?.precision ?? Precision.day;
  late EventStatus _status = widget.initial?.status ?? EventStatus.scheduled;
  late final List<PersonLink> _links =
      widget.initial?.people.toList() ??
      [PersonLink(personId: widget.people.first.id, role: Role.participant)];
  late final Set<String> _previousEventIds =
      widget.initial?.previousEventIds.toSet() ?? <String>{};
  late final _previousQuery = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _start.dispose();
    _end.dispose();
    _placeDetail.dispose();
    _description.dispose();
    _tags.dispose();
    _previousQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _EditorDialog(
    title: Text(widget.initial == null ? '新增事件' : '编辑事件'),
    contentWidth: 900,
    content: SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('基本信息'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '事件标题 *'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 132,
                child: DropdownButtonFormField<EventStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: '状态'),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  dropdownColor: AtlasPalette.card,
                  items: EventStatus.values
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(status.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _status = value!;
                    if (_status == EventStatus.scheduled) {
                      _precision = Precision.day;
                      _end.clear();
                    }
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<Precision>(
                  initialValue: _precision,
                  isDense: true,
                  decoration: const InputDecoration(labelText: '时间精度'),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  dropdownColor: AtlasPalette.card,
                  elevation: 6,
                  items:
                      (_status == EventStatus.scheduled
                              ? const [Precision.day]
                              : Precision.values)
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                value.label,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => setState(() => _precision = value!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _start,
                  readOnly: true,
                  onTap: () => _pickDate(_start),
                  decoration: InputDecoration(
                    labelText: _precision == Precision.range
                        ? '开始时间 *'
                        : _status == EventStatus.scheduled
                        ? '预定日期'
                        : _status == EventStatus.cancelled
                        ? '时间（可选）'
                        : '时间 *',
                    hintText: _status == EventStatus.scheduled
                        ? '点击选择（可留空）'
                        : '点击选择',
                    suffixIcon:
                        _status == EventStatus.scheduled &&
                            _start.text.isNotEmpty
                        ? IconButton(
                            onPressed: () => setState(_start.clear),
                            icon: const Icon(Icons.clear),
                            tooltip: '清空日期',
                          )
                        : const Icon(Icons.calendar_today, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_precision == Precision.range) ...[
            TextField(
              controller: _end,
              readOnly: true,
              onTap: () => _pickDate(_end),
              decoration: const InputDecoration(
                labelText: '结束时间',
                hintText: '点击选择',
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
            ),
            const SizedBox(height: 8),
          ],
          _sectionTitle('地点'),
          ..._locationFields(chinaRegions),
          _sectionTitle('内容'),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '描述',
              hintText: '发生了什么',
            ),
          ),
          _sectionTitle('关联'),
          Row(
            children: [
              const Text('关联人物 *'),
              const Spacer(),
              TextButton.icon(
                onPressed: _addLink,
                icon: const Icon(Icons.add),
                label: const Text('添加'),
              ),
            ],
          ),
          ...List.generate(_links.length, _linkEditor),
          if (_eligiblePreviousEvents.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('前序事件'),
                const SizedBox(width: 8),
                Text(
                  '已选 ${_previousEventIds.length}',
                  style: TextStyle(color: AtlasPalette.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _previousQuery,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: '搜索前序事件',
                suffixIcon: _previousQuery.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => setState(_previousQuery.clear),
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            ..._filteredPreviousEvents.map(
              (event) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                mouseCursor: SystemMouseCursors.click,
                hoverColor: AtlasPalette.interactiveHover,
                value: _previousEventIds.contains(event.id),
                title: Text(event.title),
                subtitle: Text(event.dateLabel),
                onChanged: (selected) => setState(() {
                  if (selected == true) {
                    _previousEventIds.add(event.id);
                  } else {
                    _previousEventIds.remove(event.id);
                  }
                }),
              ),
            ),
            if (_filteredPreviousEvents.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('没有匹配的前序事件'),
              ),
          ],
          _sectionTitle('标签'),
          const Text('选择标签'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _availableTags
                .map(
                  (tag) => FilterChip(
                    label: Text(tag),
                    selected: _split(_tags.text).contains(tag),
                    onSelected: (selected) => _toggleTag(tag, selected),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AtlasPalette.green,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(height: 1)),
      ],
    ),
  );

  List<EventItem> get _eligiblePreviousEvents =>
      widget.events
          .where(
            (event) =>
                event.id != _id &&
                (event.createdAt.isBefore(_createdAt) ||
                    (event.createdAt.isAtSameMomentAs(_createdAt) &&
                        event.id.compareTo(_id) < 0)),
          )
          .toList()
        ..sort((left, right) {
          final created = left.createdAt.compareTo(right.createdAt);
          return created == 0 ? left.id.compareTo(right.id) : created;
        });

  List<EventItem> get _filteredPreviousEvents {
    final query = _previousQuery.text.trim().toLowerCase();
    if (query.isEmpty) return _eligiblePreviousEvents;
    return _eligiblePreviousEvents.where((event) {
      final content = [
        event.title,
        event.dateLabel,
        event.place,
        event.description,
        ...event.tags,
      ].join(' ').toLowerCase();
      return content.contains(query);
    }).toList();
  }

  List<String> get _availableTags {
    final tags = {
      ...widget.customTags,
      ...widget.events.expand((event) => event.tags),
      ..._split(_tags.text),
    }.toList()..sort();
    return tags;
  }

  void _toggleTag(String tag, bool selected) {
    final tags = _split(_tags.text).toSet();
    if (selected) {
      tags.add(tag);
    } else {
      tags.remove(tag);
    }
    setState(() => _tags.text = tags.join('，'));
  }

  List<Widget> _locationFields(ChinaRegions regions) {
    final cities = _province == null
        ? const <String>[]
        : regions.citiesFor(_province!);
    final districts = _province == null || _city == null
        ? const <String>[]
        : regions.districtsFor(_province!, _city!);
    return [
      DropdownButtonFormField<String>(
        key: ValueKey('country-$_country'),
        initialValue: _country,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '国家/地区 *'),
        hint: const Text('请选择'),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        dropdownColor: AtlasPalette.card,
        elevation: 6,
        items: eventLocationCountries
            .map(
              (country) =>
                  DropdownMenuItem(value: country, child: Text(country)),
            )
            .toList(),
        onChanged: (value) => setState(() {
          _country = value;
          _province = null;
          _city = null;
          _district = null;
        }),
      ),
      const SizedBox(height: 8),
      if (_country == '中国') ...[
        DropdownButtonFormField<String>(
          key: ValueKey('province-$_province'),
          initialValue: _province,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '省级地区 *'),
          hint: const Text('请选择'),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          dropdownColor: AtlasPalette.card,
          elevation: 6,
          items: regions.provinces
              .map(
                (province) =>
                    DropdownMenuItem(value: province, child: Text(province)),
              )
              .toList(),
          onChanged: (value) => setState(() {
            _province = value;
            _city = null;
            _district = null;
          }),
        ),
        const SizedBox(height: 8),
        if (_province != null && cities.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('city-$_city'),
            initialValue: _city,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '城市 *'),
            hint: const Text('请选择'),
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            dropdownColor: AtlasPalette.card,
            elevation: 6,
            items: cities
                .map((city) => DropdownMenuItem(value: city, child: Text(city)))
                .toList(),
            onChanged: (value) => setState(() {
              _city = value;
              _district = null;
            }),
          ),
          const SizedBox(height: 8),
        ],
        if (_city != null && districts.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('district-$_district'),
            initialValue: _district,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '区/县 *'),
            hint: const Text('请选择'),
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            dropdownColor: AtlasPalette.card,
            elevation: 6,
            items: districts
                .map(
                  (district) =>
                      DropdownMenuItem(value: district, child: Text(district)),
                )
                .toList(),
            onChanged: (value) => setState(() => _district = value),
          ),
          const SizedBox(height: 8),
        ],
      ],
      TextField(
        controller: _placeDetail,
        decoration: const InputDecoration(
          labelText: '详细地点（可选）',
          hintText: '街道、社区或场所',
        ),
      ),
    ];
  }

  Widget _linkEditor(int index) {
    final link = _links[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: link.personId,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              dropdownColor: AtlasPalette.card,
              elevation: 6,
              items: widget.people
                  .map(
                    (person) => DropdownMenuItem(
                      value: person.id,
                      child: Text(person.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(
                () => _links[index] = PersonLink(
                  personId: value!,
                  role: link.role,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<Role>(
              initialValue: link.role,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              dropdownColor: AtlasPalette.card,
              elevation: 6,
              items: Role.values
                  .map(
                    (role) =>
                        DropdownMenuItem(value: role, child: Text(role.label)),
                  )
                  .toList(),
              onChanged: (value) => setState(
                () => _links[index] = PersonLink(
                  personId: link.personId,
                  role: value!,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _links.length == 1
                ? null
                : () => setState(() => _links.removeAt(index)),
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
    );
  }

  void _addLink() {
    final used = _links.map((link) => link.personId).toSet();
    final candidate = widget.people
        .where((person) => !used.contains(person.id))
        .firstOrNull;
    if (candidate != null) {
      setState(
        () => _links.add(
          PersonLink(personId: candidate.id, role: Role.participant),
        ),
      );
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    DateTime? initial;
    if (controller.text.isNotEmpty) {
      final parts = controller.text.split('-');
      initial = DateTime(
        int.tryParse(parts[0]) ?? now.year,
        parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1,
        parts.length > 2 ? int.tryParse(parts[2]) ?? 1 : 1,
      );
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      initialDatePickerMode: _precision == Precision.year
          ? DatePickerMode.year
          : DatePickerMode.day,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(size: const Size(340, 600)),
        child: child!,
      ),
    );
    if (picked == null) return;
    final formatted = switch (_precision) {
      Precision.year => '${picked.year}',
      Precision.month =>
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}',
      Precision.day || Precision.range =>
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
    };
    setState(() => controller.text = formatted);
  }

  void _save() {
    final title = _title.text.trim();
    final start = _start.text.trim();
    final end = _precision == Precision.range ? _end.text.trim() : null;
    final location = EventLocation(
      country: _country,
      province: _province,
      city: _city,
      district: _district,
      detail: _placeDetail.text,
    );
    if (title.isEmpty || _links.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写标题，并关联至少一位人物。')));
      return;
    }
    if (_status != EventStatus.scheduled &&
        _status != EventStatus.cancelled &&
        start.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('进行中或已结束事件必须填写时间。')));
      return;
    }
    if (_status == EventStatus.scheduled &&
        start.isNotEmpty &&
        _parseLocalDate(start) == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('预定日期必须精确到日。')));
      return;
    }
    if (location.validationMessage(chinaRegions) case final message?) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (_precision == Precision.range &&
        end != null &&
        end.isNotEmpty &&
        end.compareTo(start) < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结束时间不能早于开始时间。')));
      return;
    }
    final now = DateTime.now();
    Navigator.pop(
      context,
      EventItem(
        id: _id,
        title: title,
        precision: _status == EventStatus.scheduled
            ? Precision.day
            : _precision,
        start: start,
        end: _status == EventStatus.scheduled ? null : end,
        place: location.value,
        description: _description.text.trim(),
        tags: _split(_tags.text),
        sources: widget.initial?.sources ?? const [],
        people: _links,
        createdAt: _createdAt,
        updatedAt: now,
        status: _status,
        previousEventIds: _previousEventIds.toList()..sort(),
      ),
    );
  }
}

List<String> _split(String value) => value
    .split(RegExp('[，,]'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toSet()
    .toList();
