import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_settings.dart';
import 'app_update.dart';
import 'archive.dart';
import 'archive_repository.dart';
import 'event_location.dart';
import 'sync_models.dart';
import 'sync_service.dart';

Color _onPaletteColor(Color color) =>
    color.computeLuminance() > 0.5 ? Colors.black : Colors.white;

Color _detailSurface(BuildContext context) =>
    Theme.of(context).colorScheme.surface;

Color _detailGroupSurface(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerHigh;

Color _personSurface(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainer;

Color _personOnSurface(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface;

Color _personTagSurface(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerHigh;

Color _personTagOnSurface(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface;

Color _eventTagSurface(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerHigh;

Color _eventTagOnSurface(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface;

Color _eventStatusColor(BuildContext context, EventStatus status) =>
    switch (status) {
      EventStatus.scheduled => Theme.of(
        context,
      ).colorScheme.surfaceContainerHigh,
      EventStatus.active => Theme.of(context).colorScheme.primary,
      EventStatus.completed => Theme.of(context).colorScheme.surfaceContainer,
      EventStatus.cancelled => Theme.of(context).colorScheme.error,
    };

Color _eventStatusTextColor(BuildContext context, EventStatus status) =>
    switch (status) {
      EventStatus.scheduled => Theme.of(context).colorScheme.onSurface,
      EventStatus.active => Theme.of(context).colorScheme.onPrimary,
      EventStatus.completed => Theme.of(context).colorScheme.onSurface,
      EventStatus.cancelled => Theme.of(context).colorScheme.onError,
    };

String _formatLocalDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _shortDateTime(DateTime date) =>
    date.toLocal().toIso8601String().replaceFirst('T', ' ').substring(0, 16);

DateTime? _parseLocalDate(String value) {
  if (value.length != 10) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null || _formatLocalDate(parsed) != value) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
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
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  children: [content],
                ),
              ),
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
const _syncAccessChannel = MethodChannel('local.munch.eventatlas/sync-access');

List<Map<String, dynamic>> widgetEventPayload(Archive archive) {
  final events = [...archive.events]
    ..sort((left, right) {
      final date = right.start.compareTo(left.start);
      if (date != 0) return date;
      final updated = right.updatedAt.compareTo(left.updatedAt);
      return updated != 0 ? updated : left.id.compareTo(right.id);
    });
  return events
      .take(6)
      .map(
        (event) => {
          'id': event.id,
          'title': event.title,
          'precision': event.precision.name,
          'start': event.start,
          'end': event.end,
          'place': event.place,
          'description': event.description,
          'status': event.status.name,
          'tags': event.tags,
        },
      )
      .toList();
}

Future<void> _updateWidget(Archive archive) async {
  if (!Platform.isMacOS) return;
  try {
    await _widgetChannel.invokeMethod<void>('update', {
      'events': widgetEventPayload(archive),
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

class PersonEventAtlasApp extends StatefulWidget {
  const PersonEventAtlasApp({super.key, this.repository});

  final ArchiveRepository? repository;

  @override
  State<PersonEventAtlasApp> createState() => _PersonEventAtlasAppState();
}

class _PersonEventAtlasAppState extends State<PersonEventAtlasApp> {
  late final ArchiveRepository _repository =
      widget.repository ?? ArchiveRepository();
  late final AppUpdateService _updateService = AppUpdateService();
  AppSettings _settings = AppSettings.defaults;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      _settings = await _repository.loadSettings();
      await _restoreSyncDirectoryAccess();
    } catch (_) {
      _settings = AppSettings.defaults;
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _restoreSyncDirectoryAccess() async {
    if (!Platform.isMacOS ||
        !_settings.syncEnabled ||
        _settings.syncDirectoryBookmark == null) {
      return;
    }
    try {
      final restored = await _syncAccessChannel.invokeMapMethod<String, String>(
        'startBookmark',
        _settings.syncDirectoryBookmark,
      );
      final directory = restored?['path'];
      final bookmark = restored?['bookmark'];
      if (directory == null || bookmark == null) {
        throw PlatformException(code: 'invalid_sync_bookmark');
      }
      final next = _settings.copyWith(
        syncDirectory: directory,
        syncDirectoryBookmark: bookmark,
      );
      if (next.syncDirectory != _settings.syncDirectory ||
          next.syncDirectoryBookmark != _settings.syncDirectoryBookmark) {
        _settings = next;
        await _repository.saveSettings(next);
      }
    } on PlatformException catch (_) {
      await _clearSyncDirectoryBookmark();
    } on MissingPluginException {
      await _clearSyncDirectoryBookmark();
    }
  }

  Future<void> _clearSyncDirectoryBookmark() async {
    final next = _settings.copyWith(clearSyncDirectoryBookmark: true);
    _settings = next;
    try {
      await _repository.saveSettings(next);
    } catch (_) {
      // The settings page will still ask for the directory again this run.
    }
  }

  Future<void> _saveSettings(AppSettings next) async {
    final previous = _settings;
    setState(() => _settings = next);
    try {
      await _repository.saveSettings(next);
    } catch (_) {
      if (mounted) setState(() => _settings = previous);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thing',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      locale: const Locale('zh', 'CN'),
      theme: _atlasTheme(_settings.primaryColor, Brightness.light),
      darkTheme: _atlasTheme(_settings.primaryColor, Brightness.dark),
      themeMode: switch (_settings.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      home: _ready
          ? _AtlasGrainFrame(
              child: ArchiveHome(
                repository: _repository,
                settings: _settings,
                onSettingsChanged: _saveSettings,
                onCheckForUpdates: _updateService.checkForUpdate,
                onInstallUpdate: _updateService.downloadAndInstall,
              ),
            )
          : const _AtlasGrainFrame(
              child: Scaffold(body: Center(child: Text('正在打开本地档案…'))),
            ),
    );
  }
}

ThemeData _atlasTheme(AppPrimaryColor primaryColor, Brightness brightness) {
  final primary = Color(primaryColor.value);
  final companion = Color(primaryColor.companionValue);
  final canvas = brightness == Brightness.dark ? Colors.black : Colors.white;
  final surface = Color.alphaBlend(companion.withAlpha(30), canvas);
  final surfaceLow = Color.alphaBlend(companion.withAlpha(46), canvas);
  final surfaceHigh = Color.alphaBlend(companion.withAlpha(68), canvas);
  final surfaceHighest = Color.alphaBlend(companion.withAlpha(92), canvas);
  final onPrimary = _onPaletteColor(primary);
  final onCompanion = _onPaletteColor(companion);
  final onSurface = brightness == Brightness.dark ? Colors.white : Colors.black;
  final error = brightness == Brightness.dark ? Colors.white : Colors.black;
  final scheme =
      (brightness == Brightness.dark ? ColorScheme.dark : ColorScheme.light)(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: surfaceHigh,
        onPrimaryContainer: onSurface,
        secondary: companion,
        onSecondary: onCompanion,
        secondaryContainer: surfaceHighest,
        onSecondaryContainer: onPrimary,
        tertiary: companion,
        onTertiary: onCompanion,
        error: error,
        onError: brightness == Brightness.dark ? Colors.black : Colors.white,
        errorContainer: error,
        onErrorContainer: brightness == Brightness.dark
            ? Colors.black
            : Colors.white,
        surface: surface,
        onSurface: onSurface,
        surfaceDim: canvas,
        surfaceBright: surfaceLow,
        surfaceContainerLowest: canvas,
        surfaceContainerLow: surfaceLow,
        surfaceContainer: surfaceHigh,
        surfaceContainerHigh: surfaceHighest,
        surfaceContainerHighest: Color.alphaBlend(
          companion.withAlpha(116),
          canvas,
        ),
        onSurfaceVariant: onSurface.withAlpha(170),
        outline: onSurface.withAlpha(120),
        outlineVariant: surfaceHigh,
        inverseSurface: onSurface,
        onInverseSurface: onPrimary,
        inversePrimary: surfaceHigh,
        surfaceTint: Colors.transparent,
        background: surface,
        onBackground: onSurface,
        surfaceVariant: surfaceLow,
      );
  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: surface,
    colorScheme: scheme,
    cardTheme: CardThemeData(
      color: surfaceLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: scheme.outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surface,
      selectedIconTheme: IconThemeData(color: onSurface),
      selectedLabelTextStyle: TextStyle(
        color: onSurface,
        fontWeight: FontWeight.w700,
      ),
      indicatorColor: surfaceHigh,
      indicatorShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      useIndicator: true,
      unselectedIconTheme: IconThemeData(color: onSurface.withAlpha(170)),
      unselectedLabelTextStyle: TextStyle(color: onSurface.withAlpha(170)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: surfaceHigh,
      indicatorShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      overlayColor: const WidgetStatePropertyAll<Color?>(Colors.transparent),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceLow,
      side: BorderSide.none,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      labelStyle: TextStyle(color: onSurface, fontSize: 11),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        side: BorderSide(color: scheme.outline),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surfaceLow,
      textStyle: TextStyle(color: onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceHigh,
      contentTextStyle: TextStyle(color: onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    textTheme:
        (brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light())
            .textTheme
            .apply(bodyColor: onSurface, displayColor: onSurface),
  );
}

class _AtlasGrainFrame extends StatelessWidget {
  const _AtlasGrainFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final grainColor =
        (brightness == Brightness.dark ? Colors.white : Colors.black).withAlpha(
          10,
        );
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              key: const ValueKey('atlas-grain'),
              painter: _AtlasGrainPainter(grainColor),
            ),
          ),
        ),
      ],
    );
  }
}

class _AtlasGrainPainter extends CustomPainter {
  const _AtlasGrainPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const cellSize = 22.0;
    final columns = (size.width / cellSize).ceil();
    final rows = (size.height / cellSize).ceil();
    final paint = Paint()..color = color;
    // ponytail: fixed grid keeps painting cheap; use a texture asset only if this repeats visibly.
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final index = row * columns + column;
        final x = column * cellSize + (index * 17) % 19 + 1;
        final y = row * cellSize + (index * 29) % 19 + 1;
        canvas.drawRect(
          Rect.fromLTWH(x, y, index.isEven ? 1.0 : 0.7, 1.0),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AtlasGrainPainter oldDelegate) =>
      oldDelegate.color != color;
}

enum ArchiveView { timeline, people, tags, settings }

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
  const ArchiveHome({
    super.key,
    this.repository,
    this.settings = AppSettings.defaults,
    this.onSettingsChanged,
    this.onCheckForUpdates,
    this.onInstallUpdate,
  });

  final ArchiveRepository? repository;
  final AppSettings settings;
  final Future<void> Function(AppSettings settings)? onSettingsChanged;
  final Future<AppUpdateRelease?> Function()? onCheckForUpdates;
  final Future<void> Function(
    AppUpdateRelease release, {
    UpdateProgress? onProgress,
  })?
  onInstallUpdate;

  @override
  State<ArchiveHome> createState() => _ArchiveHomeState();
}

class _ArchiveHomeState extends State<ArchiveHome> {
  late final ArchiveRepository _repository =
      widget.repository ?? ArchiveRepository();
  late final SyncService _syncService = SyncService(_repository);
  Archive? _archive;
  SyncMetadata _syncMetadata = const SyncMetadata();
  ArchiveView _view = ArchiveView.timeline;
  ArchiveFilters _filters = const ArchiveFilters();
  String _query = '';
  String? _personId;
  String? _eventId;
  String? _error;
  bool _syncBusy = false;
  final _detailViewportKey = GlobalKey();
  Rect? _detailOrigin;
  String? _detailPreviewEventId;
  bool _detailOpening = false;
  bool _detailClosing = false;
  bool _detailEditing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _repository.purgeExpiredTrash(widget.settings.trashRetention);
    await _reload();
    await _configureSync();
  }

  @override
  void didUpdateWidget(covariant ArchiveHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.syncEnabled != widget.settings.syncEnabled ||
        oldWidget.settings.syncDirectory != widget.settings.syncDirectory ||
        oldWidget.settings.syncDirectoryBookmark !=
            widget.settings.syncDirectoryBookmark) {
      unawaited(_configureSync());
    }
    if (oldWidget.settings.trashRetention != widget.settings.trashRetention) {
      unawaited(_repository.purgeExpiredTrash(widget.settings.trashRetention));
    }
  }

  @override
  void dispose() {
    unawaited(_syncService.dispose());
    unawaited(_repository.close());
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final archive = await _repository.load();
      final syncMetadata = await _repository.loadSyncMetadata();
      unawaited(_updateWidget(archive));
      if (mounted) {
        setState(() {
          _archive = archive;
          _syncMetadata = syncMetadata;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开本地档案，请从备份恢复。');
    }
  }

  Future<void> _configureSync() async {
    await _syncService.stopWatching();
    final directory = widget.settings.syncDirectory;
    if (!widget.settings.syncEnabled ||
        directory == null ||
        directory.isEmpty) {
      if (!mounted) return;
      setState(() {});
      return;
    }
    if (Platform.isMacOS && widget.settings.syncDirectoryBookmark == null) {
      if (mounted) {
        setState(
          () => _syncMetadata = const SyncMetadata(
            status: '需要重新选择同步目录',
            error: 'macOS 需要重新选择同步目录以恢复访问权限。',
          ),
        );
      }
      return;
    }
    try {
      await _syncService.watch(directory, () => _syncNow(silent: false));
      await _syncNow(silent: true);
    } catch (_) {
      if (mounted) _notice('无法监视同步目录。');
    }
  }

  Future<void> _syncNow({
    bool silent = false,
    Map<String, SyncConflictChoice> resolutions = const {},
    bool confirmInitialMerge = false,
  }) async {
    final directory = widget.settings.syncDirectory;
    if (!widget.settings.syncEnabled ||
        directory == null ||
        directory.isEmpty ||
        (Platform.isMacOS && widget.settings.syncDirectoryBookmark == null)) {
      return;
    }
    if (_syncBusy) return;
    _syncBusy = true;
    try {
      final report = await _syncService.synchronize(
        directory: directory,
        retention: widget.settings.trashRetention,
        resolutions: resolutions,
        confirmInitialMerge: confirmInitialMerge,
      );
      if (!mounted) return;
      setState(() => _syncMetadata = report.metadata);
      if (report.retentionDays != null &&
          report.retentionDays != widget.settings.trashRetention.days) {
        final save = widget.onSettingsChanged;
        if (save != null) {
          await save(
            widget.settings.copyWith(
              trashRetention: trashRetentionFromDays(report.retentionDays!),
            ),
          );
        }
      }
      if (report.applied) await _reload();
      if (report.outcome == SyncOutcome.failed && mounted) {
        _notice(report.message ?? '同步失败。');
      } else if (report.outcome == SyncOutcome.preview && !silent && mounted) {
        final confirmed = await _confirm(
          '确认首次合并',
          report.message ?? '确认合并本机和同步文件中的档案吗？',
          confirmLabel: '确认合并',
        );
        if (confirmed && mounted) {
          _syncBusy = false;
          await _syncNow(confirmInitialMerge: true);
        }
      } else if (report.outcome == SyncOutcome.conflicts &&
          !silent &&
          mounted) {
        final choices = await showDialog<Map<String, SyncConflictChoice>>(
          context: context,
          builder: (_) =>
              SyncConflictDialog(conflicts: report.metadata.conflicts),
        );
        if (choices != null && mounted) {
          _syncBusy = false;
          await _syncNow(resolutions: choices);
        }
      }
    } catch (_) {
      if (mounted) _notice('同步失败，本机资料保持不变。');
    } finally {
      _syncBusy = false;
    }
  }

  Future<bool> _write(Future<void> Function() action) async {
    try {
      await action();
      await _reload();
      await _syncNow(silent: true);
      return true;
    } on FormatException catch (error) {
      _notice(error.message.toString());
    } catch (_) {
      _notice('保存失败：资料尚未写入本机。');
    }
    return false;
  }

  void _notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Person? get _selectedPerson =>
      _archive?.people.where((person) => person.id == _personId).firstOrNull;
  EventItem? get _selectedEvent =>
      _archive?.events.where((event) => event.id == _eventId).firstOrNull;

  void _selectPerson(String id) {
    final detailAlreadyOpen = _personId != null || _eventId != null;
    setState(() {
      _personId = id;
      _eventId = null;
      _detailEditing = false;
      _view = ArchiveView.people;
      _detailOpening = false;
      _detailClosing = false;
      if (!detailAlreadyOpen) _detailOrigin = null;
    });
  }

  void _selectEvent(String id) {
    final detailAlreadyOpen = _personId != null || _eventId != null;
    setState(() {
      _eventId = id;
      _personId = null;
      _detailEditing = false;
      _view = ArchiveView.timeline;
      _detailOpening = false;
      _detailClosing = false;
      if (!detailAlreadyOpen) _detailOrigin = null;
    });
  }

  void _openEventFromCard(String id, Rect globalOrigin) {
    if (_detailOpening ||
        _detailClosing ||
        _personId != null ||
        _eventId != null) {
      return;
    }
    final renderObject = _detailViewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) {
      _selectEvent(id);
      return;
    }
    final origin =
        renderObject.globalToLocal(globalOrigin.topLeft) & globalOrigin.size;
    setState(() {
      _detailOrigin = origin;
      _detailPreviewEventId = id;
      _detailOpening = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_detailOpening) return;
      setState(() {
        _eventId = id;
        _personId = null;
        _view = ArchiveView.timeline;
        _detailOpening = false;
      });
    });
  }

  void _clearSelection() {
    if ((_personId != null || _eventId != null) && _detailOrigin != null) {
      setState(() => _detailClosing = true);
      return;
    }
    setState(() {
      _personId = null;
      _eventId = null;
      _detailEditing = false;
      _detailOpening = false;
      _detailClosing = false;
      _detailOrigin = null;
      _detailPreviewEventId = null;
    });
  }

  void _finishDetailClose() {
    if (!_detailClosing || !mounted) return;
    setState(() {
      _personId = null;
      _eventId = null;
      _detailEditing = false;
      _detailOpening = false;
      _detailClosing = false;
      _detailOrigin = null;
      _detailPreviewEventId = null;
    });
  }

  Future<void> _editPerson([Person? initial]) =>
      _editPersonWithOptions(initial);

  Future<void> _editPersonWithoutDetail(Person person) =>
      _editPersonWithOptions(person, openDetail: false);

  Future<void> _editPersonWithOptions(
    Person? initial, {
    bool openDetail = true,
  }) async {
    final person = await showDialog<Person>(
      context: context,
      builder: (_) => PersonEditor(
        initial: initial,
        personTags: _archive == null ? const [] : _personTags(_archive!),
      ),
    );
    if (person == null) return;
    await _write(() => _repository.savePerson(person));
    if (mounted) {
      if (openDetail) {
        _selectPerson(person.id);
      } else {
        _clearSelection();
      }
    }
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
        eventTags: _eventTags(archive),
        defaultPrecision: widget.settings.defaultPrecision,
      ),
    );
    if (event == null) return;
    await _write(() => _repository.saveEvent(event));
    if (mounted) _selectEvent(event.id);
  }

  Future<void> _saveDetailEvent(EventItem event) async {
    if (await _write(() => _repository.saveEvent(event)) && mounted) {
      setState(() => _detailEditing = false);
    }
  }

  Future<void> _savePersonTags(List<String> tags) async {
    await _write(() => _repository.savePersonTags(tags));
  }

  Future<void> _saveEventTags(List<String> tags) async {
    await _write(() => _repository.saveEventTags(tags));
  }

  Future<void> _deletePersonTag(String tag) =>
      _deleteTag(EntityType.person, tag);

  Future<void> _deleteEventTag(String tag) => _deleteTag(EntityType.event, tag);

  Future<void> _deleteTag(EntityType type, String tag) async {
    final archive = _archive;
    if (archive == null) return;
    final personTags = type == EntityType.person
        ? archive.effectivePersonTags.where((item) => item != tag).toList()
        : archive.effectivePersonTags;
    final eventTags = type == EntityType.event
        ? archive.effectiveEventTags.where((item) => item != tag).toList()
        : archive.effectiveEventTags;
    final updated = archive.copyWith(
      customTags: {...personTags, ...eventTags}.toList()..sort(),
      personTags: personTags,
      eventTags: eventTags,
      people: type == EntityType.person
          ? archive.people
                .map(
                  (person) => person.copyWith(
                    tags: person.tags.where((item) => item != tag).toList(),
                  ),
                )
                .toList()
          : archive.people,
      events: type == EntityType.event
          ? archive.events
                .map(
                  (event) => event.copyWith(
                    tags: event.tags.where((item) => item != tag).toList(),
                  ),
                )
                .toList()
          : archive.events,
    );
    await _write(() => _repository.replace(updated));
  }

  Future<void> _deletePerson(Person person) async {
    final immediate =
        widget.settings.trashRetention == TrashRetention.immediate;
    final confirmed = await _confirm(
      immediate ? '永久删除人物' : '移入回收站',
      immediate
          ? '确定永久删除「${person.name}」吗？删除后无法恢复。'
          : '确定将「${person.name}」移入回收站吗？可在保留期限内恢复。',
      confirmLabel: immediate ? '永久删除' : '移入回收站',
    );
    if (!confirmed) return;
    try {
      final deleted = await _repository.deletePerson(person.id);
      if (!deleted) {
        _notice('该人物仍关联事件，请先删除或编辑相关事件。');
        return;
      }
      if (immediate) {
        await _repository.purgeExpiredTrash(TrashRetention.immediate);
      }
      _clearSelection();
      await _reload();
      await _syncNow(silent: true);
    } catch (_) {
      _notice('删除失败，资料尚未改变。');
    }
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
    final immediate =
        widget.settings.trashRetention == TrashRetention.immediate;
    if (!await _confirm(
      immediate ? '永久删除事件' : '移入回收站',
      immediate
          ? '确定永久删除「${event.title}」吗？删除后无法恢复。'
          : '确定将「${event.title}」移入回收站吗？可在保留期限内恢复。',
      confirmLabel: immediate ? '永久删除' : '移入回收站',
    )) {
      return;
    }
    await _write(() async {
      await _repository.deleteEvent(event.id);
      if (immediate) {
        await _repository.purgeExpiredTrash(TrashRetention.immediate);
      }
    });
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
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON 档案', extensions: ['json']),
        ],
      );
      if (file == null) return;
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
    try {
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
    } catch (_) {
      if (mounted) _notice('无法导出档案文件。');
    }
  }

  Future<void> _chooseSyncDirectory() async {
    try {
      final directory = await getDirectoryPath(confirmButtonText: '选择同步目录');
      if (directory == null || !mounted) return;
      String? bookmark;
      if (Platform.isMacOS) {
        bookmark = await _syncAccessChannel.invokeMethod<String>(
          'createBookmark',
          directory,
        );
        if (bookmark == null || bookmark.isEmpty) {
          throw PlatformException(code: 'invalid_sync_bookmark');
        }
      }
      final save = widget.onSettingsChanged;
      if (save == null) return;
      await save(
        widget.settings.copyWith(
          syncDirectory: directory,
          syncDirectoryBookmark: bookmark,
          clearSyncDirectoryBookmark: !Platform.isMacOS,
          syncEnabled: true,
        ),
      );
      if (mounted) _notice('同步目录已保存。');
    } on PlatformException catch (_) {
      if (mounted) _notice('无法保存 macOS 同步目录权限，请重新选择。');
    } on MissingPluginException {
      if (mounted) _notice('当前 macOS 版本不支持持久化同步目录权限。');
    } catch (_) {
      if (mounted) _notice('无法选择同步目录。');
    }
  }

  Future<void> _openTrash() async {
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => TrashDialog(
          retention: widget.settings.trashRetention,
          loadEntries: _repository.loadTrash,
          onRestore: (entry) async {
            await _repository.restoreTrash(entry);
            await _reload();
            await _syncNow(silent: true);
          },
          onDeleteForever: (entry) async {
            await _repository.purgeTrashEntry(entry);
            await _reload();
            await _syncNow(silent: true);
          },
        ),
      );
    } on FormatException catch (error) {
      _notice(error.message.toString());
    } catch (_) {
      _notice('回收站操作失败。');
    }
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
        final utilityView = tagsView || _view == ArchiveView.settings;
        final selected = _selectedPerson ?? _selectedEvent;
        final detailOpen = selected != null && !utilityView;
        final detailVisible = detailOpen || _detailOpening || _detailClosing;
        final previewEventId = _eventId ?? _detailPreviewEventId;
        final previewEvent = previewEventId == null
            ? null
            : archive.events
                  .where((event) => event.id == previewEventId)
                  .firstOrNull;
        final list = switch (_view) {
          ArchiveView.timeline => TimelineList(
            events: events,
            people: archive.people,
            onOpen: _selectEvent,
            onOpenFromCard: _openEventFromCard,
          ),
          ArchiveView.people => PeopleList(
            people: people,
            events: archive.events,
            onOpen: _selectPerson,
            onEdit: (person) => unawaited(_editPersonWithoutDetail(person)),
          ),
          ArchiveView.tags => CustomTagsPage(
            personTags: _personTags(archive),
            eventTags: _eventTags(archive),
            personCounts: {
              for (final tag in _personTags(archive))
                tag: archive.people
                    .where((person) => person.tags.contains(tag))
                    .length,
            },
            eventCounts: {
              for (final tag in _eventTags(archive))
                tag: archive.events
                    .where((event) => event.tags.contains(tag))
                    .length,
            },
            onChanged: (type, tags) => type == EntityType.person
                ? _savePersonTags(tags)
                : _saveEventTags(tags),
            onDelete: (type, tag) => type == EntityType.person
                ? _deletePersonTag(tag)
                : _deleteEventTag(tag),
          ),
          ArchiveView.settings => SettingsPage(
            settings: widget.settings,
            syncMetadata: _syncMetadata,
            onChanged: (settings) async {
              final save = widget.onSettingsChanged;
              if (save == null) return;
              try {
                await save(settings);
              } catch (_) {
                if (mounted) _notice('设置保存失败。');
              }
            },
            onImport: _importArchive,
            onExport: _exportArchive,
            onChooseSyncDirectory: _chooseSyncDirectory,
            onSyncNow: () => _syncNow(silent: false),
            onOpenTrash: _openTrash,
            onCheckForUpdates: widget.onCheckForUpdates,
            onInstallUpdate: widget.onInstallUpdate,
          ),
        };
        final browseControls = utilityView
            ? const SizedBox.shrink()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: FilterBar(
                          archive: archive,
                          filters: _filters,
                          tagType: _view == ArchiveView.timeline
                              ? EntityType.event
                              : EntityType.person,
                          onChanged: (value) =>
                              setState(() => _filters = value),
                        ),
                      ),
                      if (desktop)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 16, 12),
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 42),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
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
                  if (_view == ArchiveView.timeline)
                    ReminderPanel(
                      events: _dueEvents(archive),
                      onOpen: _selectEvent,
                    ),
                ],
              );
        final detail = ArchiveDetail(
          fullPage: true,
          person: _selectedPerson,
          event: _selectedEvent,
          editing: _detailEditing,
          archive: archive,
          onClose: _clearSelection,
          onPerson: _selectPerson,
          onEvent: _selectEvent,
          onEditPerson: _editPerson,
          onStartEventEdit: () => setState(() => _detailEditing = true),
          onCancelEventEdit: () => setState(() => _detailEditing = false),
          onSaveEvent: _saveDetailEvent,
          onDeletePerson: _deletePerson,
          onDeleteEvent: _deleteEvent,
          onCancelEvent: _cancelEvent,
          onTransitionEvent: _transitionEvent,
          onPostponeEvent: _postponeEvent,
        );
        final workspace = Stack(
          key: _detailViewportKey,
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                _Header(view: _view),
                Expanded(
                  child: Column(
                    children: [
                      browseControls,
                      Expanded(child: list),
                    ],
                  ),
                ),
              ],
            ),
            if (previewEvent != null)
              _DetailExpansion(
                visible: detailVisible,
                expanded: detailOpen && !_detailOpening && !_detailClosing,
                origin: _detailOrigin,
                preview: EventCard(
                  event: previewEvent,
                  people: {
                    for (final person in archive.people) person.id: person.name,
                  },
                ),
                onClosed: _finishDetailClose,
                child: detail,
              ),
          ],
        );
        return Scaffold(
          body: SafeArea(
            child: desktop
                ? Row(
                    children: [
                      _DesktopSidebar(
                        view: _view,
                        onChanged: (view) => setState(() {
                          _view = view;
                          _personId = null;
                          _eventId = null;
                          _detailEditing = false;
                          _detailOrigin = null;
                          _detailPreviewEventId = null;
                          _detailOpening = false;
                          _detailClosing = false;
                          _filters = _filters.copyWith(clearTag: true);
                        }),
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
                    _detailEditing = false;
                    _detailOrigin = null;
                    _detailPreviewEventId = null;
                    _detailOpening = false;
                    _detailClosing = false;
                    _filters = _filters.copyWith(clearTag: true);
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
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: '设置',
                    ),
                  ],
                ),
          floatingActionButton: desktop || utilityView
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

  List<String> _personTags(Archive archive) {
    final tags = {
      ...archive.effectivePersonTags,
      ...archive.people.expand((person) => person.tags),
    };
    return tags.toList()..sort();
  }

  List<String> _eventTags(Archive archive) {
    final tags = {
      ...archive.effectiveEventTags,
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset('assets/logo.png', width: 34, height: 34),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thing',
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'THING · ARCHIVE',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 9),
            ),
          ],
        ),
      ],
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({required this.view, required this.onChanged});

  final ArchiveView view;
  final ValueChanged<ArchiveView> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 264,
      child: ColoredBox(
        color: colors.surface,
        child: Column(
          children: [
            Expanded(
              child: NavigationRail(
                backgroundColor: Colors.transparent,
                extended: true,
                minExtendedWidth: 264,
                groupAlignment: -0.78,
                selectedIndex: view == ArchiveView.settings ? null : view.index,
                onDestinationSelected: (index) =>
                    onChanged(ArchiveView.values[index]),
                leading: const Padding(
                  padding: EdgeInsets.fromLTRB(12, 22, 12, 28),
                  child: _Brand(),
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SidebarSettingsButton(
                    selected: view == ArchiveView.settings,
                    onPressed: () => onChanged(ArchiveView.settings),
                  ),
                  const SizedBox(height: 12),
                  Divider(color: colors.outlineVariant),
                  const SizedBox(height: 14),
                  Text(
                    '你的资料只保存在此设备。\n设置页可管理备份与偏好。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarSettingsButton extends StatelessWidget {
  const _SidebarSettingsButton({
    required this.selected,
    required this.onPressed,
  });

  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedColor = colors.surfaceContainerHigh;
    return Material(
      color: selected ? selectedColor : Colors.transparent,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: InkWell(
        onTap: onPressed,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.settings : Icons.settings_outlined,
                  color: selected ? colors.onSurface : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  '设置',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.view});
  final ArchiveView view;
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
                'THING · ARCHIVE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(switch (view) {
                ArchiveView.timeline => '事件时间线',
                ArchiveView.people => '人物目录',
                ArchiveView.tags => '标签管理',
                ArchiveView.settings => '设置',
              }, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
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
    this.tagType = EntityType.event,
    required this.onChanged,
  });
  final Archive archive;
  final ArchiveFilters filters;
  final EntityType tagType;
  final ValueChanged<ArchiveFilters> onChanged;
  @override
  Widget build(BuildContext context) {
    final tags =
        tagType == EntityType.person
              ? {
                  ...archive.effectivePersonTags,
                  ...archive.people.expand((person) => person.tags),
                }.toList()
              : {
                  ...archive.effectiveEventTags,
                  ...archive.events.expand((event) => event.tags),
                }.toList()
          ..sort();
    final tagLabel = tagType == EntityType.person ? '人物标签' : '事件标签';
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
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
              tagLabel,
              filters.tag,
              [
                DropdownMenuItem(value: null, child: Text('$tagLabel：全部')),
                ...tags.map(
                  (tag) => DropdownMenuItem(
                    value: tag,
                    child: Text('$tagLabel：#$tag'),
                  ),
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
        color: value == null
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border.all(
          color: value == null
              ? Theme.of(context).colorScheme.outline
              : Theme.of(context).colorScheme.outline,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: _AtlasDropdown<T>(
        value: value,
        items: items,
        hint: Text('$label：全部'),
        decoration: const InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          suffixIconConstraints: BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        onChanged: (next) {
          if (next != null || T.toString().contains('null')) {
            onChanged(next as T);
          }
        },
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
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
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
    this.onOpenFromCard,
  });
  final List<EventItem> events;
  final List<Person> people;
  final ValueChanged<String> onOpen;
  final void Function(String id, Rect origin)? onOpenFromCard;
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
      itemBuilder: (context, index) {
        final event = events[index];
        final cardKey = GlobalKey();
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
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        child: Container(
                          width: 1,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    Positioned(
                      top: 24,
                      left: 4,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: EventCard(
                  key: cardKey,
                  event: event,
                  people: names,
                  onTap: () {
                    final renderObject = cardKey.currentContext
                        ?.findRenderObject();
                    if (onOpenFromCard != null && renderObject is RenderBox) {
                      final origin =
                          renderObject.localToGlobal(Offset.zero) &
                          renderObject.size;
                      onOpenFromCard!(event.id, origin);
                    } else {
                      onOpen(event.id);
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.people,
    this.onTap,
  });

  final EventItem event;
  final Map<String, String> people;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      mouseCursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      onTap: onTap,
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
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (event.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        event.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, height: 1.45),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Chip(
                        backgroundColor: _eventStatusColor(
                          context,
                          event.status,
                        ),
                        label: Text(
                          event.status.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: _eventStatusTextColor(context, event.status),
                          ),
                        ),
                      ),
                      ...event.tags.map(
                        (tag) => Chip(
                          backgroundColor: _eventTagSurface(context),
                          label: Text(
                            '#$tag',
                            style: TextStyle(
                              color: _eventTagOnSurface(context),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      ..._orderedPeople(event.people).map(
                        (link) => Chip(
                          backgroundColor: _personSurface(context),
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 15,
                                color: _personOnSurface(context),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${people[link.personId] ?? '未知人物'} · ${link.role.label}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _personOnSurface(context),
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
  );
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
    required this.onEdit,
  });
  final List<Person> people;
  final List<EventItem> events;
  final ValueChanged<String> onOpen;
  final ValueChanged<Person> onEdit;
  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return const EmptyState(title: '没有匹配的人物', text: '调整搜索条件，或新建人物档案。');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = math.min(200.0, constraints.maxWidth);
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: people.map((person) {
                final count = events
                    .where(
                      (event) => event.people.any(
                        (link) => link.personId == person.id,
                      ),
                    )
                    .length;
                return SizedBox(
                  width: cardWidth,
                  height: 144,
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      hoverColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      onTap: () => onOpen(person.id),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: _personSurface(context),
                                  child: Text(
                                    person.name.characters.first,
                                    style: TextStyle(
                                      color: _personOnSurface(context),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    person.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '直接编辑',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 30,
                                    minHeight: 30,
                                  ),
                                  iconSize: 18,
                                  style: IconButton.styleFrom(
                                    foregroundColor: _personOnSurface(context),
                                  ),
                                  onPressed: () => onEdit(person),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              person.bio.isEmpty ? '尚未添加简介' : person.bio,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '关联 $count 个事件',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _DetailExpansion extends StatefulWidget {
  const _DetailExpansion({
    required this.visible,
    required this.expanded,
    required this.origin,
    required this.preview,
    required this.onClosed,
    required this.child,
  });

  final bool visible;
  final bool expanded;
  final Rect? origin;
  final Widget preview;
  final VoidCallback onClosed;
  final Widget child;

  @override
  State<_DetailExpansion> createState() => _DetailExpansionState();
}

class _DetailExpansionState extends State<_DetailExpansion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.expanded ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _DetailExpansion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    if (widget.expanded) {
      _controller.forward();
    } else {
      _close();
    }
  }

  Future<void> _close() async {
    await _controller.reverse();
    if (mounted && widget.visible && _controller.isDismissed) {
      widget.onClosed();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    key: const ValueKey('detail-expansion-animation'),
    animation: _controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final target = Rect.fromLTWH(
          0,
          0,
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final start = widget.origin ?? target;
        final progress = Curves.easeInOutCubic.transform(_controller.value);
        final rect = Rect.lerp(start, target, progress)!;
        final radius = 16 * (1 - progress);
        final child = progress < 0.62 ? widget.preview : widget.child;
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(radius)),
                child: IgnorePointer(ignoring: progress < 0.98, child: child),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class ArchiveDetail extends StatelessWidget {
  const ArchiveDetail({
    super.key,
    this.fullPage = false,
    this.person,
    this.event,
    this.editing = false,
    required this.archive,
    required this.onClose,
    required this.onPerson,
    required this.onEvent,
    required this.onEditPerson,
    required this.onStartEventEdit,
    required this.onCancelEventEdit,
    required this.onSaveEvent,
    required this.onDeletePerson,
    required this.onDeleteEvent,
    required this.onCancelEvent,
    required this.onTransitionEvent,
    required this.onPostponeEvent,
  });
  final bool fullPage;
  final Person? person;
  final EventItem? event;
  final bool editing;
  final Archive archive;
  final VoidCallback onClose;
  final ValueChanged<String> onPerson;
  final ValueChanged<String> onEvent;
  final ValueChanged<Person> onEditPerson;
  final VoidCallback onStartEventEdit;
  final VoidCallback onCancelEventEdit;
  final Future<void> Function(EventItem) onSaveEvent;
  final ValueChanged<Person> onDeletePerson;
  final ValueChanged<EventItem> onDeleteEvent;
  final ValueChanged<EventItem> onCancelEvent;
  final void Function(EventItem, EventStatus) onTransitionEvent;
  final ValueChanged<EventItem> onPostponeEvent;

  @override
  Widget build(BuildContext context) {
    final item = person ?? event;
    if (item == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final names = {for (final item in archive.people) item.id: item};
    final related = person == null
        ? const <EventItem>[]
        : archive.events
              .where(
                (item) =>
                    item.people.any((link) => link.personId == person!.id),
              )
              .toList();
    final isEditing = editing && event != null;

    Widget group(String title, IconData icon, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Material(
        color: _detailGroupSurface(context),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.outline),
          borderRadius: const BorderRadius.all(Radius.circular(14)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: colors.primary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );

    void handleAction(String action) {
      if (action == 'edit') {
        person != null ? onEditPerson(person!) : onStartEventEdit();
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
    }

    final menu = MenuAnchor(
      animated: true,
      crossAxisUnconstrained: false,
      reservedPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomEnd,
        backgroundColor: WidgetStatePropertyAll(colors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      menuChildren: [
        _detailMenuItem(context, '编辑', () => handleAction('edit')),
        if (event != null && event!.status == EventStatus.scheduled)
          _detailMenuItem(
            context,
            event!.start.isEmpty ? '设置日期' : '延期',
            () => handleAction('postpone'),
          ),
        if (event != null && event!.status == EventStatus.scheduled)
          _detailMenuItem(context, '开始', () => handleAction('start')),
        if (event != null && event!.status == EventStatus.active)
          _detailMenuItem(context, '结束', () => handleAction('complete')),
        if (event != null &&
            (event!.status == EventStatus.scheduled ||
                event!.status == EventStatus.active))
          _detailMenuItem(context, '取消事件', () => handleAction('cancel')),
        if (person != null)
          _detailMenuItem(context, '删除', () => handleAction('delete')),
        if (event != null)
          _detailMenuItem(
            context,
            '永久删除',
            () => handleAction('permanent-delete'),
          ),
      ],
      builder: (context, controller, child) => IconButton(
        tooltip: '更多操作',
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        icon: const Icon(Icons.more_horiz),
      ),
    );

    return ClipRRect(
      borderRadius: fullPage
          ? BorderRadius.zero
          : const BorderRadius.only(
              topLeft: Radius.circular(18),
              bottomLeft: Radius.circular(18),
            ),
      child: Material(
        color: fullPage ? _detailSurface(context) : colors.surface,
        shape: fullPage
            ? null
            : RoundedRectangleBorder(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
                side: BorderSide(color: colors.outline),
              ),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          padding: fullPage
              ? const EdgeInsets.fromLTRB(32, 12, 32, 40)
              : const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant, width: 1.5),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: fullPage ? '返回' : '关闭',
                    onPressed: onClose,
                    icon: Icon(fullPage ? Icons.arrow_back : Icons.close),
                  ),
                  if (fullPage) ...[
                    const SizedBox(width: 8),
                    Icon(
                      person != null
                          ? Icons.person_outline
                          : isEditing
                          ? Icons.edit_note_outlined
                          : Icons.event_note_outlined,
                      size: 20,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      person != null
                          ? '人物档案'
                          : isEditing
                          ? '编辑事件'
                          : '事件详情',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                  const Spacer(),
                  if (isEditing)
                    TextButton(
                      onPressed: onCancelEventEdit,
                      child: const Text('取消编辑'),
                    )
                  else
                    menu,
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (isEditing)
              EventEditor(
                key: ValueKey('detail-editor-${event!.id}'),
                inline: true,
                initial: event,
                people: archive.people,
                events: archive.events,
                eventTags: archive.effectiveEventTags,
                onCancel: onCancelEventEdit,
                onSaved: onSaveEvent,
              )
            else ...[
              if (person != null)
                CircleAvatar(
                  radius: 28,
                  backgroundColor: _personSurface(context),
                  child: Text(
                    person!.name.characters.first,
                    style: TextStyle(
                      color: _personOnSurface(context),
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                person != null ? '人物档案' : event!.dateLabel,
                style: TextStyle(
                  color: person != null
                      ? _personOnSurface(context)
                      : colors.primary,
                ),
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
                  backgroundColor: _eventStatusColor(context, event!.status),
                  label: Text(
                    event!.status.label,
                    style: TextStyle(
                      color: _eventStatusTextColor(context, event!.status),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DetailSection(
                  title: '事件信息',
                  values: {'时间': event!.dateLabel, '地点': event!.place},
                ),
                if (event!.tags.isNotEmpty)
                  group(
                    '事件标签',
                    Icons.sell_outlined,
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: event!.tags
                          .map(
                            (tag) => Chip(
                              backgroundColor: _eventTagSurface(context),
                              label: Text(
                                '#$tag',
                                style: TextStyle(
                                  color: _eventTagOnSurface(context),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                group(
                  '关联人物',
                  Icons.people_outline,
                  Column(
                    children: _orderedPeople(event!.people)
                        .map(
                          (link) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            mouseCursor: SystemMouseCursors.click,
                            hoverColor: Colors.transparent,
                            splashColor: Colors.transparent,
                            onTap: () => onPerson(link.personId),
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: _personSurface(context),
                              child: Icon(
                                Icons.person_outline,
                                size: 16,
                                color: _personOnSurface(context),
                              ),
                            ),
                            title: Text(names[link.personId]?.name ?? '未知人物'),
                            trailing: Text(link.role.label),
                          ),
                        )
                        .toList(),
                  ),
                ),
                if (event!.previousEventIds.isNotEmpty)
                  group(
                    '前序事件',
                    Icons.account_tree_outlined,
                    Column(
                      children: event!.previousEventIds.map((id) {
                        final previous = archive.events
                            .where((item) => item.id == id)
                            .firstOrNull;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          mouseCursor: previous == null
                              ? SystemMouseCursors.basic
                              : SystemMouseCursors.click,
                          hoverColor: Colors.transparent,
                          splashColor: Colors.transparent,
                          onTap: previous == null ? null : () => onEvent(id),
                          title: Text(previous?.title ?? '未知事件'),
                          subtitle: Text(previous?.dateLabel ?? '关联资料缺失'),
                          trailing: const Icon(Icons.chevron_right),
                        );
                      }).toList(),
                    ),
                  ),
              ],
              if (person != null) ...[
                DetailSection(
                  title: '资料',
                  values: {
                    '备注': person!.notes,
                    '来源': person!.sources.join('；'),
                  },
                ),
                if (person!.tags.isNotEmpty)
                  group(
                    '人物标签',
                    Icons.sell_outlined,
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: person!.tags
                          .map(
                            (tag) => Chip(
                              backgroundColor: _personTagSurface(context),
                              label: Text(
                                '#$tag',
                                style: TextStyle(
                                  color: _personTagOnSurface(context),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                group(
                  '相关事件',
                  Icons.event_note_outlined,
                  related.isEmpty
                      ? const Text('暂无关联事件')
                      : Column(
                          children: related
                              .map(
                                (item) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  mouseCursor: SystemMouseCursors.click,
                                  hoverColor: Colors.transparent,
                                  splashColor: Colors.transparent,
                                  onTap: () => onEvent(item.id),
                                  title: Text(item.title),
                                  subtitle: Text(item.dateLabel),
                                  trailing: const Icon(Icons.chevron_right),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.title, required this.values});
  final String title;
  final Map<String, String> values;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = values.entries.where((entry) => entry.value.isNotEmpty);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: _detailGroupSurface(context),
        border: Border.all(color: colors.outline),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      entry.key,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                  Expanded(child: Text(entry.value)),
                ],
              ),
            ),
          ),
          if (entries.isEmpty)
            Text('暂无内容', style: TextStyle(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

Widget _detailMenuItem(
  BuildContext context,
  String label,
  VoidCallback onPressed,
) => MenuItemButton(
  onPressed: onPressed,
  style: MenuItemButton.styleFrom(
    alignment: AlignmentDirectional.centerStart,
    foregroundColor: Theme.of(context).colorScheme.onSurface,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  ),
  child: Text(label),
);

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

class _AtlasDropdown<T> extends StatefulWidget {
  const _AtlasDropdown({
    super.key,
    required this.value,
    required this.items,
    this.onChanged,
    this.decoration = const InputDecoration(),
    this.hint,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final Widget? hint;

  @override
  State<_AtlasDropdown<T>> createState() => _AtlasDropdownState<T>();
}

class _AtlasDropdownState<T> extends State<_AtlasDropdown<T>> {
  late final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite ? constraints.maxWidth : null;
      final colors = Theme.of(context).colorScheme;
      final selected = widget.items
          .where((item) => item.value == widget.value)
          .firstOrNull;
      final enabled = widget.onChanged != null && widget.items.isNotEmpty;
      final menuChildren = widget.items
          .map((item) => _menuItem(context, item, width, colors, enabled))
          .toList();
      final menuStyle = MenuStyle(
        alignment: AlignmentDirectional.bottomStart,
        backgroundColor: WidgetStatePropertyAll(colors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: width == null
            ? null
            : WidgetStatePropertyAll(Size(width, 0)),
        maximumSize: width == null
            ? null
            : WidgetStatePropertyAll(Size(width, 360)),
        visualDensity: VisualDensity.standard,
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      );

      return MenuAnchor(
        animated: menuChildren.length < 30,
        childFocusNode: _focusNode,
        crossAxisUnconstrained: false,
        reservedPadding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        style: menuStyle,
        menuChildren: menuChildren,
        builder: (context, controller, child) {
          final isOpen = controller.isOpen;
          final decoration = widget.decoration
              .copyWith(
                enabled: enabled,
                suffixIcon:
                    widget.decoration.suffixIcon ??
                    Icon(isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down),
              )
              .applyDefaults(Theme.of(context).inputDecorationTheme);
          final anchor = Semantics(
            button: true,
            expanded: isOpen,
            child: InkWell(
              onTap: enabled
                  ? () {
                      if (isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    }
                  : null,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              child: InputDecorator(
                decoration: decoration,
                isFocused: isOpen,
                isEmpty: selected == null && widget.hint == null,
                child: selected?.child ?? widget.hint,
              ),
            ),
          );
          return width == null ? IntrinsicWidth(child: anchor) : anchor;
        },
      );
    },
  );

  Widget _menuItem(
    BuildContext context,
    DropdownMenuItem<T> item,
    double? width,
    ColorScheme colors,
    bool enabled,
  ) {
    final button = MenuItemButton(
      onPressed: enabled && item.enabled
          ? () => widget.onChanged!(item.value)
          : null,
      style: MenuItemButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        foregroundColor: colors.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      child: item.child,
    );
    return width == null ? button : SizedBox(width: width, child: button);
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    this.syncMetadata = const SyncMetadata(),
    required this.onChanged,
    required this.onImport,
    required this.onExport,
    this.onChooseSyncDirectory,
    this.onSyncNow,
    this.onOpenTrash,
    this.onCheckForUpdates,
    this.onInstallUpdate,
  });

  final AppSettings settings;
  final SyncMetadata syncMetadata;
  final Future<void> Function(AppSettings settings) onChanged;
  final Future<void> Function() onImport;
  final Future<void> Function() onExport;
  final Future<void> Function()? onChooseSyncDirectory;
  final Future<void> Function()? onSyncNow;
  final Future<void> Function()? onOpenTrash;
  final Future<AppUpdateRelease?> Function()? onCheckForUpdates;
  final Future<void> Function(
    AppUpdateRelease release, {
    UpdateProgress? onProgress,
  })?
  onInstallUpdate;

  void _change(AppSettings next) => unawaited(onChanged(next));

  @override
  Widget build(BuildContext context) {
    final directory = settings.syncDirectory;
    final chooseDirectory = onChooseSyncDirectory ?? () async {};
    final syncNow = onSyncNow ?? () async {};
    final openTrash = onOpenTrash ?? () async {};
    final syncSection = _settingsSection(
      context,
      title: '自托管同步与回收站',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用同步'),
            subtitle: Text(
              directory ?? '选择一个由 Syncthing 或 Nextcloud Desktop 管理的文件夹。',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            value: settings.syncEnabled,
            onChanged: (enabled) {
              if (enabled &&
                  (directory == null ||
                      (Platform.isMacOS &&
                          settings.syncDirectoryBookmark == null))) {
                unawaited(chooseDirectory());
              } else {
                _change(settings.copyWith(syncEnabled: enabled));
              }
            },
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: chooseDirectory,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(directory == null ? '选择同步目录' : '更换目录'),
              ),
              FilledButton.icon(
                onPressed:
                    settings.syncEnabled &&
                        directory != null &&
                        (!Platform.isMacOS ||
                            settings.syncDirectoryBookmark != null)
                    ? syncNow
                    : null,
                icon: const Icon(Icons.sync),
                label: const Text('立即同步'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '状态：${syncMetadata.status}${syncMetadata.lastSyncAt == null ? '' : ' · 最近同步 ${_shortDateTime(syncMetadata.lastSyncAt!)}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (syncMetadata.error != null) ...[
            const SizedBox(height: 4),
            Text(
              syncMetadata.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (syncMetadata.conflicts.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: syncNow,
              icon: const Icon(Icons.warning_amber_outlined),
              label: Text('处理 ${syncMetadata.conflicts.length} 条冲突'),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '回收站保留期限',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<TrashRetention>(
                        value: settings.trashRetention,
                        isExpanded: true,
                        items: TrashRetention.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) async {
                          if (value == null) return;
                          if (value == TrashRetention.immediate) {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('立即清理回收站？'),
                                content: const Text('现有回收站记录会永久删除，之后无法恢复。'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('永久清理'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                          }
                          _change(settings.copyWith(trashRetention: value));
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: openTrash,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('打开回收站'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '同步文件只包含档案、回收站和删除标记；主题、主色、默认时间精度及同步路径只保存在本机。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    final themeSection = _settingsSection(
      context,
      title: '主题模式',
      child: SegmentedButton<AppThemeMode>(
        segments: AppThemeMode.values
            .map(
              (mode) => ButtonSegment<AppThemeMode>(
                value: mode,
                label: Text(mode.label),
              ),
            )
            .toList(),
        selected: {settings.themeMode},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) {
            _change(settings.copyWith(themeMode: selection.first));
          }
        },
      ),
    );
    final colorSection = _settingsSection(
      context,
      title: '配色搭配',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: AppPrimaryColor.values
            .map(
              (color) => ChoiceChip(
                key: ValueKey('primary-${color.name}'),
                label: Text(color.label),
                avatar: SizedBox(
                  width: 28,
                  height: 16,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(4)),
                    child: Row(
                      children: [
                        Expanded(child: ColoredBox(color: Color(color.value))),
                        Expanded(
                          child: ColoredBox(color: Color(color.companionValue)),
                        ),
                      ],
                    ),
                  ),
                ),
                selectedColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHigh,
                checkmarkColor: Theme.of(context).colorScheme.onSurface,
                selected: settings.primaryColor == color,
                onSelected: (_) =>
                    _change(settings.copyWith(primaryColor: color)),
              ),
            )
            .toList(),
      ),
    );
    final precisionSection = _settingsSection(
      context,
      title: '新建事件默认时间精度',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AtlasDropdown<Precision>(
            value: settings.defaultPrecision,
            decoration: const InputDecoration(labelText: '时间精度'),
            items: Precision.values
                .map(
                  (precision) => DropdownMenuItem(
                    value: precision,
                    child: Text(precision.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                _change(settings.copyWith(defaultPrecision: value));
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Text(
              '只影响新建事件，编辑已有事件保持原值。',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('应用偏好', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                '设置会自动保存在本机，不会写入导出的档案文件。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _settingsSection(
                context,
                title: '数据管理',
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: onImport,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('导入 JSON'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: onExport,
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('导出 JSON'),
                    ),
                  ],
                ),
              ),
              AppUpdatePanel(
                onCheckForUpdates: onCheckForUpdates,
                onInstallUpdate: onInstallUpdate,
              ),
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 720
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: themeSection),
                          const SizedBox(width: 16),
                          Expanded(child: colorSection),
                          const SizedBox(width: 16),
                          Expanded(child: precisionSection),
                        ],
                      )
                    : Column(
                        children: [
                          themeSection,
                          colorSection,
                          precisionSection,
                        ],
                      ),
              ),
              syncSection,
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingsSection(
    BuildContext context, {
    required String title,
    required Widget child,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class AppUpdatePanel extends StatefulWidget {
  const AppUpdatePanel({
    super.key,
    this.onCheckForUpdates,
    this.onInstallUpdate,
  });

  final Future<AppUpdateRelease?> Function()? onCheckForUpdates;
  final Future<void> Function(
    AppUpdateRelease release, {
    UpdateProgress? onProgress,
  })?
  onInstallUpdate;

  @override
  State<AppUpdatePanel> createState() => _AppUpdatePanelState();
}

class _AppUpdatePanelState extends State<AppUpdatePanel> {
  AppUpdateRelease? _release;
  String? _message;
  bool _checking = false;
  bool _installing = false;
  double? _progress;

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _message = null;
      _release = null;
    });
    try {
      final check =
          widget.onCheckForUpdates ?? AppUpdateService().checkForUpdate;
      final release = await check();
      if (!mounted) return;
      setState(() {
        _release = release;
        _message = release == null
            ? '当前已是最新版本。'
            : '发现新版本 ${release.tagName}，可以下载并安装。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _install() async {
    final release = _release;
    if (release == null) return;
    setState(() {
      _installing = true;
      _progress = 0;
      _message = '正在下载更新…';
    });
    try {
      final install =
          widget.onInstallUpdate ?? AppUpdateService().downloadAndInstall;
      await install(
        release,
        onProgress: (value) {
          if (!mounted) return;
          setState(() {
            _progress = value;
            _message = '正在下载更新 ${value * 100 ~/ 1}%…';
          });
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _message = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('应用更新', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '当前版本 $appVersionLabel。更新包从 GitHub Release 获取。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _checking || _installing ? null : _checkForUpdates,
                icon: const Icon(Icons.refresh),
                label: Text(_checking ? '检查中…' : '检查更新'),
              ),
              if (_release != null)
                FilledButton.icon(
                  onPressed: _installing ? null : _install,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(_installing ? '安装中…' : '下载并安装'),
                ),
            ],
          ),
          if (_installing && _progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress),
          ],
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(
              _message!,
              style: TextStyle(
                color: _release == null && _message != '当前已是最新版本。'
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_release != null && _release!.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _release!.notes.trim(),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );
}

class SyncConflictDialog extends StatefulWidget {
  const SyncConflictDialog({super.key, required this.conflicts});

  final List<SyncConflict> conflicts;

  @override
  State<SyncConflictDialog> createState() => _SyncConflictDialogState();
}

class _SyncConflictDialogState extends State<SyncConflictDialog> {
  late final Map<String, SyncConflictChoice> _choices = {
    for (final conflict in widget.conflicts)
      conflict.key: SyncConflictChoice.local,
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('同步冲突'),
    content: SizedBox(
      width: 560,
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: widget.conflicts.length,
        separatorBuilder: (_, _) => const Divider(height: 20),
        itemBuilder: (context, index) {
          final conflict = widget.conflicts[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(conflict.label),
            subtitle: Text('${conflict.entityType.label} · 选择保留本机或同步文件版本'),
            trailing: SegmentedButton<SyncConflictChoice>(
              segments: const [
                ButtonSegment(
                  value: SyncConflictChoice.local,
                  label: Text('本机'),
                ),
                ButtonSegment(
                  value: SyncConflictChoice.remote,
                  label: Text('远端'),
                ),
              ],
              selected: {_choices[conflict.key]!},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  setState(() => _choices[conflict.key] = selection.first);
                }
              },
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('稍后处理'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _choices),
        child: const Text('应用选择'),
      ),
    ],
  );
}

class TrashDialog extends StatefulWidget {
  const TrashDialog({
    super.key,
    required this.retention,
    required this.loadEntries,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final TrashRetention retention;
  final Future<List<TrashEntry>> Function() loadEntries;
  final Future<void> Function(TrashEntry entry) onRestore;
  final Future<void> Function(TrashEntry entry) onDeleteForever;

  @override
  State<TrashDialog> createState() => _TrashDialogState();
}

class _TrashDialogState extends State<TrashDialog> {
  List<TrashEntry> _entries = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final entries = await widget.loadEntries();
      if (mounted) {
        setState(() {
          _entries = entries;
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '无法读取回收站。';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('回收站'),
    content: SizedBox(
      width: 620,
      height: 420,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _entries.isEmpty
          ? const EmptyState(title: '回收站为空', text: '删除的人物和事件会在这里保留一段时间。')
          : ListView.separated(
              itemCount: _entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final expires = entry.deletedAt.toLocal().add(
                  Duration(days: widget.retention.days),
                );
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(
                    entry.entityType == EntityType.person
                        ? Icons.person_outline
                        : Icons.event_outlined,
                  ),
                  title: Text(entry.title),
                  subtitle: Text(
                    '${entry.entityType.label} · 删除于 ${_shortDateTime(entry.deletedAt)}'
                    '${widget.retention == TrashRetention.immediate ? '' : ' · 到期 ${_shortDateTime(expires)}'}',
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => _restore(entry),
                        child: const Text('恢复'),
                      ),
                      IconButton(
                        tooltip: '永久删除',
                        onPressed: () => _deleteForever(entry),
                        icon: const Icon(Icons.delete_forever_outlined),
                      ),
                    ],
                  ),
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );

  Future<void> _restore(TrashEntry entry) async {
    try {
      await widget.onRestore(entry);
      await _refresh();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } catch (_) {
      if (mounted) setState(() => _error = '恢复失败，请检查关联人物和前序事件。');
    }
  }

  Future<void> _deleteForever(TrashEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除'),
        content: Text('确定永久删除「${entry.title}」吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.onDeleteForever(entry);
      await _refresh();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } catch (_) {
      if (mounted) setState(() => _error = '永久删除失败。');
    }
  }
}

class CustomTagsPage extends StatefulWidget {
  const CustomTagsPage({
    super.key,
    required this.personTags,
    required this.eventTags,
    required this.personCounts,
    required this.eventCounts,
    required this.onChanged,
    required this.onDelete,
  });

  final List<String> personTags;
  final List<String> eventTags;
  final Map<String, int> personCounts;
  final Map<String, int> eventCounts;
  final Future<void> Function(EntityType type, List<String> tags) onChanged;
  final Future<void> Function(EntityType type, String tag) onDelete;

  @override
  State<CustomTagsPage> createState() => _CustomTagsPageState();
}

class _CustomTagsPageState extends State<CustomTagsPage> {
  final _personController = TextEditingController();
  final _eventController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _personController.dispose();
    _eventController.dispose();
    super.dispose();
  }

  List<String> _tags(EntityType type) =>
      type == EntityType.person ? widget.personTags : widget.eventTags;

  Map<String, int> _counts(EntityType type) =>
      type == EntityType.person ? widget.personCounts : widget.eventCounts;

  TextEditingController _controller(EntityType type) =>
      type == EntityType.person ? _personController : _eventController;

  Future<void> _add(EntityType type) async {
    final controller = _controller(type);
    final tag = controller.text.trim();
    if (tag.isEmpty) return;
    final tags = {..._tags(type), tag}.toList()..sort();
    await _save(type, tags);
    if (mounted) controller.clear();
  }

  Future<void> _remove(EntityType type, String tag) async {
    if (_saving) return;
    final label = type.label;
    final count = _counts(type)[tag] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('「#$tag」关联 $count 个$label，删除后只会从$label中移除。是否继续？'),
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
      await widget.onDelete(type, tag);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save(EntityType type, List<String> tags) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onChanged(type, tags);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _tagSection(BuildContext context, EntityType type) {
    final label = type.label;
    final tags = _tags(type);
    final counts = _counts(type);
    final controller = _controller(type);
    final tagSurface = type == EntityType.person
        ? _personTagSurface(context)
        : _eventTagSurface(context);
    final tagOnSurface = type == EntityType.person
        ? _personTagOnSurface(context)
        : _eventTagOnSurface(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$label标签',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: tagOnSurface),
                  ),
                ),
                Text(
                  '${tags.length} 个',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '只用于$label编辑器和$label筛选。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: !_saving,
                    onSubmitted: (_) => _add(type),
                    decoration: InputDecoration(
                      labelText: '新增$label标签',
                      hintText: type == EntityType.person
                          ? '例如：建筑师、家人'
                          : '例如：旅行、长期项目',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _add(type),
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (tags.isEmpty)
              Text(
                '还没有$label标签。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: tags
                    .map(
                      (tag) => SizedBox(
                        width: 150,
                        child: Card(
                          color: tagSurface,
                          surfaceTintColor: Colors.transparent,
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '#$tag',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: tagOnSurface,
                                        ),
                                      ),
                                      Text(
                                        '${counts[tag] ?? 0} 个$label',
                                        style: TextStyle(
                                          color: tagOnSurface,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: '删除标签',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 30,
                                    minHeight: 30,
                                  ),
                                  iconSize: 18,
                                  style: IconButton.styleFrom(
                                    foregroundColor: tagOnSurface,
                                  ),
                                  onPressed: _saving
                                      ? null
                                      : () => _remove(type, tag),
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
    );
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
            Text('标签管理', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '人物标签和事件标签分别维护，编辑时只显示对应类型的标签。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final sections = [
                  _tagSection(context, EntityType.person),
                  _tagSection(context, EntityType.event),
                ];
                if (constraints.maxWidth < 720) {
                  return Column(
                    children: [
                      sections[0],
                      const SizedBox(height: 16),
                      sections[1],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: sections[0]),
                    const SizedBox(width: 16),
                    Expanded(child: sections[1]),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ],
  );
}

class PersonEditor extends StatefulWidget {
  const PersonEditor({super.key, this.initial, this.personTags = const []});
  final Person? initial;
  final List<String> personTags;
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
            children: _availableTags.map((tag) {
              final selected = _split(_tags.text).contains(tag);
              return FilterChip(
                backgroundColor: _personTagSurface(context),
                selectedColor: _personTagSurface(context),
                checkmarkColor: _personTagOnSurface(context),
                labelStyle: TextStyle(
                  color: selected
                      ? _personTagOnSurface(context)
                      : Theme.of(context).colorScheme.onSurface,
                ),
                label: Text(tag),
                selected: selected,
                onSelected: (selected) => _toggleTag(tag, selected),
              );
            }).toList(),
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
    final tags = {...widget.personTags, ..._split(_tags.text)}.toList()..sort();
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
    this.eventTags = const [],
    this.defaultPrecision = Precision.day,
    this.inline = false,
    this.onCancel,
    this.onSaved,
  });
  final EventItem? initial;
  final List<Person> people;
  final List<EventItem> events;
  final List<String> eventTags;
  final Precision defaultPrecision;
  final bool inline;
  final VoidCallback? onCancel;
  final FutureOr<void> Function(EventItem event)? onSaved;
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
  late Precision _precision =
      widget.initial?.precision ?? widget.defaultPrecision;
  late EventStatus _status =
      widget.initial?.status ??
      (widget.defaultPrecision == Precision.day
          ? EventStatus.scheduled
          : EventStatus.completed);
  late final List<PersonLink> _links =
      widget.initial?.people.toList() ??
      [PersonLink(personId: widget.people.first.id, role: Role.participant)];
  late final Set<String> _previousEventIds =
      widget.initial?.previousEventIds.toSet() ?? <String>{};
  late final _previousQuery = TextEditingController();
  WorldRegions? _worldRegions;
  var _locationEdited = false;

  @override
  void initState() {
    super.initState();
    if (_country != null && _country != '中国') _loadWorldRegions();
  }

  Future<void> _loadWorldRegions() async {
    try {
      final regions = await WorldRegions.load();
      if (!mounted) return;
      if (!_locationEdited && _country != null && _country != '中国') {
        final parsed = EventLocation.fromStored(
          widget.initial?.place ?? '',
          chinaRegions: chinaRegions,
          worldRegions: regions,
        );
        _province = parsed.province;
        _city = parsed.city;
        _placeDetail.text = parsed.detail;
      }
      setState(() => _worldRegions = regions);
    } catch (_) {
      if (mounted) setState(() => _worldRegions = const WorldRegions.empty());
    }
  }

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
  Widget build(BuildContext context) {
    final content = SizedBox(
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
                  autofocus: !widget.inline,
                  decoration: const InputDecoration(labelText: '事件标题 *'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 132,
                child: _AtlasDropdown<EventStatus>(
                  value: _status,
                  decoration: const InputDecoration(labelText: '状态'),
                  items: EventStatus.values
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(status.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _status = value;
                      if (_status == EventStatus.scheduled) {
                        _precision = Precision.day;
                        _end.clear();
                      }
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: _AtlasDropdown<Precision>(
                  value: _precision,
                  decoration: const InputDecoration(
                    labelText: '时间精度',
                    isDense: true,
                  ),
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
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _precision = value);
                    }
                  },
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
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
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
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                mouseCursor: SystemMouseCursors.click,
                hoverColor: Colors.transparent,
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
            children: _availableTags.map((tag) {
              final selected = _split(_tags.text).contains(tag);
              return FilterChip(
                backgroundColor: _eventTagSurface(context),
                selectedColor: _eventTagSurface(context),
                checkmarkColor: _eventTagOnSurface(context),
                labelStyle: TextStyle(
                  color: selected
                      ? _eventTagOnSurface(context)
                      : Theme.of(context).colorScheme.onSurface,
                ),
                label: Text(tag),
                selected: selected,
                onSelected: (selected) => _toggleTag(tag, selected),
              );
            }).toList(),
          ),
        ],
      ),
    );
    if (widget.inline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          const SizedBox(height: 16),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              TextButton(onPressed: widget.onCancel, child: const Text('取消')),
              FilledButton(onPressed: _save, child: const Text('保存修改')),
            ],
          ),
        ],
      );
    }
    return _EditorDialog(
      title: Text(widget.initial == null ? '新增事件' : '编辑事件'),
      contentWidth: 900,
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          border: Border.all(color: colors.outline),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: const BorderRadius.all(Radius.circular(2)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
      ...widget.eventTags,
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
    final worldStates = _country == null || _country == '中国'
        ? const <WorldRegion>[]
        : _worldRegions?.statesFor(_country!) ?? const <WorldRegion>[];
    final worldCities =
        _country == null ||
            _country == '中国' ||
            _province == null ||
            _worldRegions == null
        ? const <String>[]
        : _worldRegions!.citiesFor(_country!, _province!);
    return [
      _AtlasDropdown<String>(
        key: ValueKey('country-$_country'),
        value: _country,
        decoration: const InputDecoration(labelText: '国家/地区 *'),
        hint: const Text('请选择'),
        items: eventLocationCountries
            .map(
              (country) =>
                  DropdownMenuItem(value: country, child: Text(country)),
            )
            .toList(),
        onChanged: (value) {
          final cachedRegions = value != null && value != '中国'
              ? WorldRegions.cached
              : null;
          setState(() {
            _locationEdited = true;
            _country = value;
            _province = null;
            _city = null;
            _district = null;
            _worldRegions = cachedRegions;
          });
          if (value != null && value != '中国') {
            if (cachedRegions == null) _loadWorldRegions();
          }
        },
      ),
      const SizedBox(height: 8),
      if (_country == '中国') ...[
        _AtlasDropdown<String>(
          key: ValueKey('province-$_province'),
          value: _province,
          decoration: const InputDecoration(labelText: '省级地区 *'),
          hint: const Text('请选择'),
          items: regions.provinces
              .map(
                (province) =>
                    DropdownMenuItem(value: province, child: Text(province)),
              )
              .toList(),
          onChanged: (value) => setState(() {
            _locationEdited = true;
            _province = value;
            _city = null;
            _district = null;
          }),
        ),
        const SizedBox(height: 8),
        if (_province != null && cities.isNotEmpty) ...[
          _AtlasDropdown<String>(
            key: ValueKey('city-$_city'),
            value: _city,
            decoration: const InputDecoration(labelText: '城市 *'),
            hint: const Text('请选择'),
            items: cities
                .map((city) => DropdownMenuItem(value: city, child: Text(city)))
                .toList(),
            onChanged: (value) => setState(() {
              _locationEdited = true;
              _city = value;
              _district = null;
            }),
          ),
          const SizedBox(height: 8),
        ],
        if (_city != null && districts.isNotEmpty) ...[
          _AtlasDropdown<String>(
            key: ValueKey('district-$_district'),
            value: _district,
            decoration: const InputDecoration(labelText: '区/县 *'),
            hint: const Text('请选择'),
            items: districts
                .map(
                  (district) =>
                      DropdownMenuItem(value: district, child: Text(district)),
                )
                .toList(),
            onChanged: (value) => setState(() {
              _locationEdited = true;
              _district = value;
            }),
          ),
          const SizedBox(height: 8),
        ],
      ],
      if (_country != null && _country != '中国') ...[
        if (_worldRegions == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (worldStates.isNotEmpty) ...[
          _AtlasDropdown<String>(
            key: ValueKey('province-$_province'),
            value: _province,
            decoration: const InputDecoration(labelText: '州/省级地区（可选）'),
            hint: const Text('请选择'),
            items: worldStates
                .map(
                  (state) => DropdownMenuItem(
                    value: state.name,
                    child: Text(state.name),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() {
              _locationEdited = true;
              _province = value;
              _city = null;
            }),
          ),
          const SizedBox(height: 8),
          if (_province != null && worldCities.isNotEmpty) ...[
            _AtlasDropdown<String>(
              key: ValueKey('city-$_city'),
              value: _city,
              decoration: const InputDecoration(labelText: '城市（可选）'),
              hint: const Text('请选择'),
              items: worldCities
                  .map(
                    (city) => DropdownMenuItem(value: city, child: Text(city)),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                _locationEdited = true;
                _city = value;
              }),
            ),
            const SizedBox(height: 8),
          ],
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
            child: _AtlasDropdown<String>(
              value: link.personId,
              items: widget.people
                  .map(
                    (person) => DropdownMenuItem(
                      value: person.id,
                      child: Text(person.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(
                  () => _links[index] = PersonLink(
                    personId: value,
                    role: link.role,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _AtlasDropdown<Role>(
              value: link.role,
              items: Role.values
                  .map(
                    (role) =>
                        DropdownMenuItem(value: role, child: Text(role.label)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(
                  () => _links[index] = PersonLink(
                    personId: link.personId,
                    role: value,
                  ),
                );
              },
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

  Future<void> _save() async {
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
    final saved = EventItem(
      id: _id,
      title: title,
      precision: _status == EventStatus.scheduled ? Precision.day : _precision,
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
    );
    final callback = widget.onSaved;
    if (callback != null) {
      await callback(saved);
    } else if (mounted) {
      Navigator.pop(context, saved);
    }
  }
}

List<String> _split(String value) => value
    .split(RegExp('[，,]'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toSet()
    .toList();
