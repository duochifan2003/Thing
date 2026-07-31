import 'china_area_data.dart';

const eventLocationCountries = <String>[
  '中国',
  '日本',
  '韩国',
  '新加坡',
  '马来西亚',
  '泰国',
  '越南',
  '美国',
  '加拿大',
  '英国',
  '法国',
  '德国',
  '意大利',
  '澳大利亚',
  '新西兰',
];

class ChinaRegions {
  const ChinaRegions(this._provinces, this._cities, this._districts);

  final Map<String, String> _provinces;
  final Map<String, String> _cities;
  final Map<String, String> _districts;

  List<String> get provinces => _provinces.values.toList(growable: false);

  List<String> citiesFor(String province) {
    final code = _codeFor(_provinces, province);
    if (code == null) return const [];
    final prefix = code.substring(0, 2);
    return [
      for (final city in _cities.entries)
        if (city.key.startsWith(prefix)) city.value,
    ];
  }

  List<String> districtsFor(String province, String city) {
    final provinceCode = _codeFor(_provinces, province);
    if (provinceCode == null) return const [];
    final cityCode = _cities.entries
        .where(
          (entry) =>
              entry.key.startsWith(provinceCode.substring(0, 2)) &&
              entry.value == city,
        )
        .map((entry) => entry.key)
        .firstOrNull;
    if (cityCode == null) return const [];
    final prefix = cityCode.substring(0, 4);
    return [
      for (final district in _districts.entries)
        if (district.key.startsWith(prefix)) district.value,
    ];
  }
}

// ponytail: stop at district/county; add towns only when records need them.
const chinaRegions = ChinaRegions(
  chinaProvinceNames,
  chinaCityNames,
  chinaDistrictNames,
);

String? _codeFor(Map<String, String> values, String name) => values.entries
    .where((entry) => entry.value == name)
    .map((entry) => entry.key)
    .firstOrNull;

class EventLocation {
  const EventLocation({
    this.country,
    this.province,
    this.city,
    this.district,
    this.detail = '',
  });

  final String? country;
  final String? province;
  final String? city;
  final String? district;
  final String detail;

  String? validationMessage(ChinaRegions chinaRegions) {
    if (country == null) return '请选择国家/地区。';
    if (country != '中国') return null;
    if (province == null) return '请选择省级地区。';
    final cities = chinaRegions.citiesFor(province!);
    if (cities.isNotEmpty && city == null) return '请选择城市。';
    final districts = city == null
        ? const <String>[]
        : chinaRegions.districtsFor(province!, city!);
    if (districts.isNotEmpty && district == null) return '请选择区/县。';
    return null;
  }

  String get value => [
    ?country,
    ?province,
    ?city,
    ?district,
    if (detail.trim().isNotEmpty) detail.trim(),
  ].join(' · ');

  static EventLocation fromStored(
    String value, {
    required ChinaRegions chinaRegions,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const EventLocation();

    final parts = trimmed
        .split(RegExp(r'\s*·\s*'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isNotEmpty && eventLocationCountries.contains(parts.first)) {
      final country = parts.removeAt(0);
      if (country != '中国') {
        return EventLocation(country: country, detail: parts.join(' · '));
      }
      return _fromChinaText(parts.join(''), chinaRegions);
    }

    final hasChinaPrefix = trimmed.startsWith('中国');
    final source = hasChinaPrefix
        ? _trimSeparator(trimmed.substring('中国'.length))
        : trimmed;
    final location = _fromChinaText(source, chinaRegions);
    if (location.province != null || hasChinaPrefix) return location;
    return EventLocation(detail: trimmed);
  }

  static EventLocation _fromChinaText(
    String source,
    ChinaRegions chinaRegions,
  ) {
    final province = _partAtStart(source, chinaRegions.provinces);
    if (province == null) return EventLocation(country: '中国', detail: source);

    var remaining = _trimSeparator(source.substring(province.length));
    final city = _partAtStart(remaining, chinaRegions.citiesFor(province));
    if (city == null) {
      return EventLocation(
        country: '中国',
        province: province,
        detail: remaining,
      );
    }

    remaining = _trimSeparator(remaining.substring(city.length));
    final district = _partAtStart(
      remaining,
      chinaRegions.districtsFor(province, city),
    );
    if (district == null) {
      return EventLocation(
        country: '中国',
        province: province,
        city: city,
        detail: remaining,
      );
    }

    return EventLocation(
      country: '中国',
      province: province,
      city: city,
      district: district,
      detail: _trimSeparator(remaining.substring(district.length)),
    );
  }
}

String? _partAtStart(String value, Iterable<String> candidates) {
  for (final candidate in candidates) {
    if (value.startsWith(candidate)) return candidate;
  }
  return null;
}

String _trimSeparator(String value) =>
    value.trim().replaceFirst(RegExp(r'^[·、，,/-]+\s*'), '');
