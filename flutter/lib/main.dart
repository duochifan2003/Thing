import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'archive.dart';
import 'archive_repository.dart';

abstract final class AtlasPalette {
  static const paper = Color(0xfff7f7f1);
  static const sidebar = Color(0xfff0f3ec);
  static const card = Color(0xfffffefa);
  static const ink = Color(0xff17211d);
  static const muted = Color(0xff758078);
  static const line = Color(0xffdfe5df);
  static const green = Color(0xff185c45);
  static const sage = Color(0xffdce7d6);
  static const accent = Color(0xffdd704c);
}

void main() => runApp(const PersonEventAtlasApp());

class PersonEventAtlasApp extends StatelessWidget {
  const PersonEventAtlasApp({super.key, this.repository});

  final ArchiveRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '事件录',
      debugShowCheckedModeBanner: false,
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
          indicatorColor: AtlasPalette.card,
          unselectedIconTheme: IconThemeData(color: Color(0xff48534c)),
          unselectedLabelTextStyle: TextStyle(color: Color(0xff48534c)),
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

enum ArchiveView { timeline, people }

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
      if (mounted)
        setState(() {
          _archive = archive;
          _error = null;
        });
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
      builder: (_) => PersonEditor(initial: initial),
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
      builder: (_) => EventEditor(initial: initial, people: archive.people),
    );
    if (event == null) return;
    await _write(() => _repository.saveEvent(event));
    if (mounted) _selectEvent(event.id);
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

  Future<void> _deleteEvent(EventItem event) async {
    if (!await _confirm('删除事件', '确定删除「${event.title}」吗？此操作不可撤销。')) return;
    await _write(() => _repository.deleteEvent(event.id));
    _clearSelection();
  }

  Future<bool> _confirm(String title, String body) async =>
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
              child: const Text('删除'),
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
    if (archive == null)
      return Scaffold(body: Center(child: Text(_error ?? '正在打开本地档案…')));
    final people = _filteredPeople(archive);
    final events = _filteredEvents(archive);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final selected = _selectedPerson ?? _selectedEvent;
        final list = _view == ArchiveView.timeline
            ? TimelineList(
                events: events,
                people: archive.people,
                onOpen: _selectEvent,
              )
            : PeopleList(
                people: people,
                events: archive.events,
                onOpen: _selectPerson,
              );
        final workspace = Column(
          children: [
            _Header(
              view: _view,
              onNewPerson: () => _editPerson(),
              onNewEvent: () => _editEvent(),
              onImport: _importArchive,
              onExport: _exportArchive,
              showArchiveMenu: !desktop,
            ),
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
            FilterBar(
              archive: archive,
              filters: _filters,
              onChanged: (value) => setState(() => _filters = value),
            ),
            Expanded(
              child: desktop
                  ? Row(
                      children: [
                        Expanded(child: list),
                        if (selected != null)
                          SizedBox(
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
                            ),
                          ),
                      ],
                    )
                  : selected != null
                  ? ArchiveDetail(
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
                    )
                  : list,
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
                  ],
                ),
          floatingActionButton: desktop
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
    required this.onNewPerson,
    required this.onNewEvent,
    required this.onImport,
    required this.onExport,
    required this.showArchiveMenu,
  });
  final ArchiveView view;
  final VoidCallback onNewPerson;
  final VoidCallback onNewEvent;
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
              Text(
                view == ArchiveView.timeline ? '事件时间线' : '人物目录',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
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
        OutlinedButton.icon(
          onPressed: onNewPerson,
          icon: const Icon(Icons.add),
          label: const Text('新增人物'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: onNewEvent,
          icon: const Icon(Icons.add),
          label: const Text('新增事件'),
        ),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          _filterMenu<String?>(
            context,
            '人物',
            filters.personId,
            [
              const DropdownMenuItem(value: null, child: Text('全部人物')),
              ...archive.people.map(
                (person) => DropdownMenuItem(
                  value: person.id,
                  child: Text(person.name),
                ),
              ),
            ],
            (value) => onChanged(
              filters.copyWith(personId: value, clearPerson: value == null),
            ),
          ),
          _filterMenu<String?>(
            context,
            '标签',
            filters.tag,
            [
              const DropdownMenuItem(value: null, child: Text('全部标签')),
              ...tags.map(
                (tag) => DropdownMenuItem(value: tag, child: Text('#$tag')),
              ),
            ],
            (value) => onChanged(
              filters.copyWith(tag: value, clearTag: value == null),
            ),
          ),
          _filterMenu<Role?>(
            context,
            '角色',
            filters.role,
            [
              const DropdownMenuItem(value: null, child: Text('全部角色')),
              ...Role.values.map(
                (role) =>
                    DropdownMenuItem(value: role, child: Text(role.label)),
              ),
            ],
            (value) => onChanged(
              filters.copyWith(role: value, clearRole: value == null),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final range = await showDialog<_DateRange>(
                context: context,
                builder: (_) =>
                    DateRangeDialog(from: filters.from, to: filters.to),
              );
              if (range != null)
                onChanged(
                  filters.copyWith(
                    from: range.from,
                    to: range.to,
                    clearFrom: range.from == null,
                    clearTo: range.to == null,
                  ),
                );
            },
            icon: const Icon(Icons.date_range_outlined, size: 18),
            label: Text(
              filters.from == null && filters.to == null
                  ? '时间范围'
                  : '${filters.from ?? '最早'} 至 ${filters.to ?? '现在'}',
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
    child: DropdownButton<T>(
      value: value,
      hint: Text(label),
      items: items,
      onChanged: (next) {
        if (next != null || T.toString().contains('null')) onChanged(next as T);
      },
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
    title: const Text('筛选时间范围'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _from,
          decoration: const InputDecoration(
            labelText: '开始时间',
            hintText: '2025-01',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _to,
          decoration: const InputDecoration(
            labelText: '结束时间',
            hintText: '2025-12',
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
                      fontSize: 12,
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
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                if (event.place.isNotEmpty)
                                  Text(
                                    event.place,
                                    style: const TextStyle(
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
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    ...event.tags.map(
                                      (tag) => Chip(label: Text('#$tag')),
                                    ),
                                    ...event.people.map(
                                      (link) => Chip(
                                        label: Text(
                                          '${names[link.personId] ?? '未知人物'} · ${link.role.label}',
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
    if (people.isEmpty)
      return const EmptyState(title: '没有匹配的人物', text: '调整搜索条件，或新建人物档案。');
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
                  if (action == 'edit')
                    person != null
                        ? onEditPerson(person!)
                        : onEditEvent(event!);
                  if (action == 'delete')
                    person != null
                        ? onDeletePerson(person!)
                        : onDeleteEvent(event!);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
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
            DetailSection(
              title: '事件信息',
              values: {
                '时间': event!.dateLabel,
                '地点': event!.place,
                '来源': event!.sources.join('；'),
              },
            ),
            const SizedBox(height: 20),
            Text('关联人物', style: Theme.of(context).textTheme.titleMedium),
            ...event!.people.map(
              (link) => ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => onPerson(link.personId),
                title: Text(names[link.personId]?.name ?? '未知人物'),
                trailing: Text(link.role.label),
              ),
            ),
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
          const SizedBox(height: 12),
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

class PersonEditor extends StatefulWidget {
  const PersonEditor({super.key, this.initial});
  final Person? initial;
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '新增人物' : '编辑人物'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: '姓名 *'),
          ),
          TextField(
            controller: _bio,
            decoration: const InputDecoration(labelText: '简介'),
          ),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: '标签',
              hintText: '建筑，访谈',
            ),
          ),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: '备注'),
          ),
          TextField(
            controller: _sources,
            decoration: const InputDecoration(labelText: '来源'),
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
  const EventEditor({super.key, this.initial, required this.people});
  final EventItem? initial;
  final List<Person> people;
  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _start = TextEditingController(text: widget.initial?.start);
  late final _end = TextEditingController(text: widget.initial?.end);
  late final _place = TextEditingController(text: widget.initial?.place);
  late final _description = TextEditingController(
    text: widget.initial?.description,
  );
  late final _tags = TextEditingController(
    text: widget.initial?.tags.join('，'),
  );
  late final _sources = TextEditingController(
    text: widget.initial?.sources.join('，'),
  );
  late Precision _precision = widget.initial?.precision ?? Precision.day;
  late List<PersonLink> _links =
      widget.initial?.people.toList() ??
      [PersonLink(personId: widget.people.first.id, role: Role.participant)];
  @override
  void dispose() {
    _title.dispose();
    _start.dispose();
    _end.dispose();
    _place.dispose();
    _description.dispose();
    _tags.dispose();
    _sources.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '新增事件' : '编辑事件'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: '事件标题 *'),
            ),
            DropdownButtonFormField<Precision>(
              value: _precision,
              decoration: const InputDecoration(labelText: '时间精度'),
              items: Precision.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _precision = value!),
            ),
            TextField(
              controller: _start,
              decoration: InputDecoration(
                labelText: _precision == Precision.range ? '开始时间 *' : '时间 *',
                hintText: _precision == Precision.year
                    ? '2025'
                    : _precision == Precision.month
                    ? '2025-03'
                    : '2025-03-18',
              ),
            ),
            if (_precision == Precision.range)
              TextField(
                controller: _end,
                decoration: const InputDecoration(
                  labelText: '结束时间',
                  hintText: '2025-05-20',
                ),
              ),
            TextField(
              controller: _place,
              decoration: const InputDecoration(labelText: '地点'),
            ),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '描述'),
            ),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(labelText: '标签'),
            ),
            TextField(
              controller: _sources,
              decoration: const InputDecoration(labelText: '来源'),
            ),
            const SizedBox(height: 16),
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
          ],
        ),
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
  Widget _linkEditor(int index) {
    final link = _links[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: link.personId,
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
              value: link.role,
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
    if (candidate != null)
      setState(
        () => _links.add(
          PersonLink(personId: candidate.id, role: Role.participant),
        ),
      );
  }

  void _save() {
    final title = _title.text.trim();
    final start = _start.text.trim();
    final end = _precision == Precision.range ? _end.text.trim() : null;
    if (title.isEmpty || start.isEmpty || _links.isEmpty) return;
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
        id: widget.initial?.id ?? 'e-${now.microsecondsSinceEpoch}',
        title: title,
        precision: _precision,
        start: start,
        end: end,
        place: _place.text.trim(),
        description: _description.text.trim(),
        tags: _split(_tags.text),
        sources: _split(_sources.text),
        people: _links,
        createdAt: widget.initial?.createdAt ?? now,
        updatedAt: now,
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
