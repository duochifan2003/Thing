import 'package:flutter_test/flutter_test.dart';
import 'package:person_event_atlas/event_location.dart';

void main() {
  test('separates a legacy Chinese place through district', () {
    final location = EventLocation.fromStored(
      '福建省厦门市海沧区',
      chinaRegions: chinaRegions,
    );

    expect(location.country, '中国');
    expect(location.province, '福建省');
    expect(location.city, '厦门市');
    expect(location.district, '海沧区');
    expect(location.detail, isEmpty);
    expect(location.value, '中国 · 福建省 · 厦门市 · 海沧区');
  });

  test('keeps text after a matched district', () {
    final location = EventLocation.fromStored(
      '福建省厦门市海沧区嵩屿街道',
      chinaRegions: chinaRegions,
    );

    expect(location.detail, '嵩屿街道');
  });

  test('requires every available Chinese administrative level', () {
    expect(const EventLocation().validationMessage(chinaRegions), '请选择国家/地区。');
    expect(
      const EventLocation(country: '中国').validationMessage(chinaRegions),
      '请选择省级地区。',
    );
    expect(
      const EventLocation(
        country: '中国',
        province: '福建省',
      ).validationMessage(chinaRegions),
      '请选择城市。',
    );
    expect(
      const EventLocation(
        country: '中国',
        province: '福建省',
        city: '厦门市',
      ).validationMessage(chinaRegions),
      '请选择区/县。',
    );
    expect(
      const EventLocation(
        country: '中国',
        province: '福建省',
        city: '厦门市',
        district: '海沧区',
      ).validationMessage(chinaRegions),
      isNull,
    );
  });

  test('parses overseas and unstructured stored places', () {
    final overseas = EventLocation.fromStored(
      '日本 · 东京',
      chinaRegions: chinaRegions,
    );
    expect(overseas.country, '日本');
    expect(overseas.detail, '东京');
    expect(overseas.value, '日本 · 东京');

    final raw = EventLocation.fromStored('咖啡馆二楼', chinaRegions: chinaRegions);
    expect(raw.country, isNull);
    expect(raw.detail, '咖啡馆二楼');

    expect(
      const EventLocation(country: '日本').validationMessage(chinaRegions),
      isNull,
    );
    expect(const EventLocation().value, isEmpty);
  });

  test('keeps partial Chinese administrative locations', () {
    final province = EventLocation.fromStored(
      '中国 · 福建省',
      chinaRegions: chinaRegions,
    );
    expect(province.province, '福建省');
    expect(province.city, isNull);
    expect(province.detail, isEmpty);

    final city = EventLocation.fromStored(
      '中国 · 福建省 · 厦门市',
      chinaRegions: chinaRegions,
    );
    expect(city.city, '厦门市');
    expect(city.district, isNull);
    expect(city.detail, isEmpty);
  });

  test('returns no descendants for unknown administrative names', () {
    expect(chinaRegions.citiesFor('不存在'), isEmpty);
    expect(chinaRegions.districtsFor('不存在', '厦门市'), isEmpty);
    expect(chinaRegions.districtsFor('福建省', '不存在'), isEmpty);
  });
}
