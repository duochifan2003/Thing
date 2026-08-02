import 'dart:convert';

import 'archive.dart';

enum AppThemeMode { system, light, dark }

enum AppPrimaryColor { forestGreen, terracotta, oceanBlue }

enum TrashRetention {
  immediate,
  sevenDays,
  thirtyDays,
  ninetyDays,
  halfYear,
  oneYear,
}

extension AppThemeModeLabel on AppThemeMode {
  String get label => switch (this) {
    AppThemeMode.system => '跟随系统',
    AppThemeMode.light => '浅色',
    AppThemeMode.dark => '深色',
  };
}

extension AppPrimaryColorLabel on AppPrimaryColor {
  String get label => switch (this) {
    AppPrimaryColor.forestGreen => '森林绿',
    AppPrimaryColor.terracotta => '陶土橙',
    AppPrimaryColor.oceanBlue => '海蓝',
  };

  int get value => switch (this) {
    AppPrimaryColor.forestGreen => 0xff185c45,
    AppPrimaryColor.terracotta => 0xffdd704c,
    AppPrimaryColor.oceanBlue => 0xff2f6690,
  };
}

extension TrashRetentionLabel on TrashRetention {
  String get label => switch (this) {
    TrashRetention.immediate => '立即',
    TrashRetention.sevenDays => '7 天',
    TrashRetention.thirtyDays => '30 天',
    TrashRetention.ninetyDays => '90 天',
    TrashRetention.halfYear => '半年',
    TrashRetention.oneYear => '一年',
  };

  int get days => switch (this) {
    TrashRetention.immediate => 0,
    TrashRetention.sevenDays => 7,
    TrashRetention.thirtyDays => 30,
    TrashRetention.ninetyDays => 90,
    TrashRetention.halfYear => 180,
    TrashRetention.oneYear => 365,
  };
}

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.primaryColor = AppPrimaryColor.forestGreen,
    this.defaultPrecision = Precision.day,
    this.syncEnabled = false,
    this.syncDirectory,
    this.trashRetention = TrashRetention.thirtyDays,
  });

  final AppThemeMode themeMode;
  final AppPrimaryColor primaryColor;
  final Precision defaultPrecision;
  final bool syncEnabled;
  final String? syncDirectory;
  final TrashRetention trashRetention;

  static const defaults = AppSettings();

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppPrimaryColor? primaryColor,
    Precision? defaultPrecision,
    bool? syncEnabled,
    String? syncDirectory,
    bool clearSyncDirectory = false,
    TrashRetention? trashRetention,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    primaryColor: primaryColor ?? this.primaryColor,
    defaultPrecision: defaultPrecision ?? this.defaultPrecision,
    syncEnabled: syncEnabled ?? this.syncEnabled,
    syncDirectory: clearSyncDirectory
        ? null
        : syncDirectory ?? this.syncDirectory,
    trashRetention: trashRetention ?? this.trashRetention,
  );

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'primaryColor': primaryColor.name,
    'defaultPrecision': defaultPrecision.name,
    'syncEnabled': syncEnabled,
    'syncDirectory': syncDirectory,
    'trashRetention': trashRetention.name,
  };

  String encode() => jsonEncode(toJson());

  factory AppSettings.decode(String source) =>
      AppSettings.fromJson(jsonDecode(source));

  factory AppSettings.fromJson(Object? value) {
    if (value is! Map) return AppSettings.defaults;
    final json = Map<String, dynamic>.from(value);
    return AppSettings(
      themeMode: _themeMode(json['themeMode']),
      primaryColor: _primaryColor(json['primaryColor']),
      defaultPrecision: _precision(json['defaultPrecision']),
      syncEnabled: json['syncEnabled'] == true,
      syncDirectory:
          json['syncDirectory'] is String &&
              (json['syncDirectory'] as String).trim().isNotEmpty
          ? (json['syncDirectory'] as String)
          : null,
      trashRetention: _trashRetention(json['trashRetention']),
    );
  }
}

TrashRetention trashRetentionFromDays(int days) => switch (days) {
  0 => TrashRetention.immediate,
  7 => TrashRetention.sevenDays,
  90 => TrashRetention.ninetyDays,
  180 => TrashRetention.halfYear,
  365 => TrashRetention.oneYear,
  _ => TrashRetention.thirtyDays,
};

AppThemeMode _themeMode(Object? value) => switch (value) {
  'light' => AppThemeMode.light,
  'dark' => AppThemeMode.dark,
  _ => AppThemeMode.system,
};

AppPrimaryColor _primaryColor(Object? value) => switch (value) {
  'terracotta' => AppPrimaryColor.terracotta,
  'oceanBlue' => AppPrimaryColor.oceanBlue,
  _ => AppPrimaryColor.forestGreen,
};

Precision _precision(Object? value) => switch (value) {
  'year' => Precision.year,
  'month' => Precision.month,
  'range' => Precision.range,
  _ => Precision.day,
};

TrashRetention _trashRetention(Object? value) => switch (value) {
  'immediate' => TrashRetention.immediate,
  'sevenDays' => TrashRetention.sevenDays,
  'ninetyDays' => TrashRetention.ninetyDays,
  'halfYear' => TrashRetention.halfYear,
  'oneYear' => TrashRetention.oneYear,
  _ => TrashRetention.thirtyDays,
};
