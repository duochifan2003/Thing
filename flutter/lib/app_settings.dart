import 'dart:convert';

import 'archive.dart';

enum AppThemeMode { system, light, dark }

enum AppPrimaryColor { forestGreen, terracotta, oceanBlue }

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

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.primaryColor = AppPrimaryColor.forestGreen,
    this.defaultPrecision = Precision.day,
  });

  final AppThemeMode themeMode;
  final AppPrimaryColor primaryColor;
  final Precision defaultPrecision;

  static const defaults = AppSettings();

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppPrimaryColor? primaryColor,
    Precision? defaultPrecision,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    primaryColor: primaryColor ?? this.primaryColor,
    defaultPrecision: defaultPrecision ?? this.defaultPrecision,
  );

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'primaryColor': primaryColor.name,
    'defaultPrecision': defaultPrecision.name,
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
    );
  }
}

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
