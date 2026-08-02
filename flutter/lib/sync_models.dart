import 'dart:convert';

import 'archive.dart';

class TrashEntry {
  const TrashEntry({
    required this.id,
    required this.entityType,
    required this.deletedAt,
    this.person,
    this.event,
  });

  final String id;
  final EntityType entityType;
  final DateTime deletedAt;
  final Person? person;
  final EventItem? event;

  String get title =>
      entityType == EntityType.person ? person?.name ?? id : event?.title ?? id;

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityType': entityType.name,
    'deletedAt': deletedAt.toUtc().toIso8601String(),
    if (person != null) 'person': person!.toJson(),
    if (event != null) 'event': event!.toJson(),
  };

  factory TrashEntry.fromJson(Map<String, dynamic> json) {
    final type = _entityType(json['entityType']);
    final id = json['id'];
    final deletedAt = json['deletedAt'];
    if (id is! String || id.isEmpty || deletedAt is! String) {
      throw const FormatException('回收站记录不完整。');
    }
    try {
      if (type == EntityType.person) {
        final value = json['person'];
        if (value is! Map) throw const FormatException('回收站人物记录不完整。');
        final person = Person.fromJson(Map<String, dynamic>.from(value));
        if (person.id != id) throw const FormatException('回收站人物 ID 不一致。');
        return TrashEntry(
          id: id,
          entityType: type,
          deletedAt: DateTime.parse(deletedAt),
          person: person,
        );
      }
      final value = json['event'];
      if (value is! Map) throw const FormatException('回收站事件记录不完整。');
      final event = EventItem.fromJson(Map<String, dynamic>.from(value));
      if (event.id != id) throw const FormatException('回收站事件 ID 不一致。');
      return TrashEntry(
        id: id,
        entityType: type,
        deletedAt: DateTime.parse(deletedAt),
        event: event,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('回收站记录日期无效。');
    }
  }
}

class SyncTombstone {
  const SyncTombstone({
    required this.id,
    required this.entityType,
    required this.deletedAt,
  });

  final String id;
  final EntityType entityType;
  final DateTime deletedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityType': entityType.name,
    'deletedAt': deletedAt.toUtc().toIso8601String(),
  };

  factory SyncTombstone.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final deletedAt = json['deletedAt'];
    if (id is! String || id.isEmpty || deletedAt is! String) {
      throw const FormatException('删除标记不完整。');
    }
    try {
      return SyncTombstone(
        id: id,
        entityType: _entityType(json['entityType']),
        deletedAt: DateTime.parse(deletedAt),
      );
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('删除标记日期无效。');
    }
  }
}

class SyncEnvelope {
  const SyncEnvelope({
    required this.archive,
    required this.trash,
    required this.tombstones,
    required this.retentionDays,
    required this.writtenAt,
    required this.deviceId,
  });

  static const format = 'Person Event Atlas Sync';
  static const version = 1;

  final Archive archive;
  final List<TrashEntry> trash;
  final List<SyncTombstone> tombstones;
  final int retentionDays;
  final DateTime writtenAt;
  final String deviceId;

  Map<String, dynamic> toJson() => {
    'format': format,
    'version': version,
    'archive': archive.toJson(),
    'trash': trash.map((entry) => entry.toJson()).toList(),
    'tombstones': tombstones.map((entry) => entry.toJson()).toList(),
    'retentionDays': retentionDays,
    'writtenAt': writtenAt.toUtc().toIso8601String(),
    'deviceId': deviceId,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory SyncEnvelope.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('同步档案格式无效。');
    final json = Map<String, dynamic>.from(decoded);
    if (json['format'] != format || json['version'] != version) {
      throw const FormatException('不支持的同步档案格式。');
    }
    final archiveValue = json['archive'];
    if (archiveValue is! Map) throw const FormatException('同步档案内容缺失。');
    final trashValue = json['trash'];
    final tombstoneValue = json['tombstones'];
    final writtenAt = json['writtenAt'];
    final deviceId = json['deviceId'];
    if (writtenAt is! String || deviceId is! String || deviceId.isEmpty) {
      throw const FormatException('同步档案元数据缺失。');
    }
    try {
      return SyncEnvelope(
        archive: Archive.decode(jsonEncode(archiveValue)),
        trash: _listOfMaps(
          trashValue,
        ).map(TrashEntry.fromJson).toList(growable: false),
        tombstones: _listOfMaps(
          tombstoneValue,
        ).map(SyncTombstone.fromJson).toList(growable: false),
        retentionDays: _retentionDays(json['retentionDays']),
        writtenAt: DateTime.parse(writtenAt),
        deviceId: deviceId,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('同步档案内容无效。');
    }
  }
}

class SyncMetadata {
  const SyncMetadata({
    this.baseline,
    this.lastSyncAt,
    this.status = '尚未同步',
    this.error,
    this.conflicts = const [],
  });

  final SyncEnvelope? baseline;
  final DateTime? lastSyncAt;
  final String status;
  final String? error;
  final List<SyncConflict> conflicts;

  Map<String, dynamic> toJson() => {
    if (baseline != null) 'baseline': baseline!.toJson(),
    if (lastSyncAt != null) 'lastSyncAt': lastSyncAt!.toUtc().toIso8601String(),
    'status': status,
    if (error != null) 'error': error,
    'conflicts': conflicts.map((conflict) => conflict.toJson()).toList(),
  };

  factory SyncMetadata.fromJson(Map<String, dynamic> json) {
    final baselineValue = json['baseline'];
    final lastSyncAt = json['lastSyncAt'];
    return SyncMetadata(
      baseline: baselineValue is Map
          ? SyncEnvelope.decode(jsonEncode(baselineValue))
          : null,
      lastSyncAt: lastSyncAt is String ? DateTime.tryParse(lastSyncAt) : null,
      status: json['status'] as String? ?? '尚未同步',
      error: json['error'] as String?,
      conflicts: _listOfMaps(
        json['conflicts'] ?? const [],
      ).map(SyncConflict.fromJson).toList(growable: false),
    );
  }
}

enum SyncConflictChoice { local, remote }

class SyncConflict {
  const SyncConflict({
    required this.entityType,
    required this.id,
    required this.local,
    required this.remote,
  });

  final EntityType entityType;
  final String id;
  final Map<String, dynamic>? local;
  final Map<String, dynamic>? remote;

  String get key => '${entityType.name}:$id';

  String get label {
    final value = local ?? remote;
    if (entityType == EntityType.person) return value?['name'] as String? ?? id;
    return value?['title'] as String? ?? id;
  }

  Map<String, dynamic> toJson() => {
    'entityType': entityType.name,
    'id': id,
    'local': local,
    'remote': remote,
  };

  factory SyncConflict.fromJson(Map<String, dynamic> json) => SyncConflict(
    entityType: _entityType(json['entityType']),
    id: json['id'] as String,
    local: json['local'] is Map
        ? Map<String, dynamic>.from(json['local'] as Map)
        : null,
    remote: json['remote'] is Map
        ? Map<String, dynamic>.from(json['remote'] as Map)
        : null,
  );
}

enum SyncOutcome {
  uploaded,
  downloaded,
  synchronized,
  preview,
  conflicts,
  failed,
}

class SyncReport {
  const SyncReport({
    required this.outcome,
    required this.metadata,
    this.retentionDays,
    this.message,
  });

  final SyncOutcome outcome;
  final SyncMetadata metadata;
  final int? retentionDays;
  final String? message;

  bool get applied =>
      outcome != SyncOutcome.preview &&
      outcome != SyncOutcome.conflicts &&
      outcome != SyncOutcome.failed;
}

class SyncMergeResult {
  const SyncMergeResult({required this.envelope, required this.conflicts});

  final SyncEnvelope envelope;
  final List<SyncConflict> conflicts;
}

class SyncMerger {
  const SyncMerger._();

  static SyncMergeResult merge({
    required SyncEnvelope local,
    required SyncEnvelope remote,
    SyncEnvelope? baseline,
    Map<String, SyncConflictChoice> resolutions = const {},
  }) {
    final localPeople = _entityVersions(local, EntityType.person);
    final remotePeople = _entityVersions(remote, EntityType.person);
    final basePeople = baseline == null
        ? const <String, _EntityVersion>{}
        : _entityVersions(baseline, EntityType.person);
    final localEvents = _entityVersions(local, EntityType.event);
    final remoteEvents = _entityVersions(remote, EntityType.event);
    final baseEvents = baseline == null
        ? const <String, _EntityVersion>{}
        : _entityVersions(baseline, EntityType.event);
    final conflicts = <SyncConflict>[];
    final people = _mergeEntities(
      type: EntityType.person,
      local: localPeople,
      remote: remotePeople,
      base: basePeople,
      resolutions: resolutions,
      conflicts: conflicts,
    );
    final events = _mergeEntities(
      type: EntityType.event,
      local: localEvents,
      remote: remoteEvents,
      base: baseEvents,
      resolutions: resolutions,
      conflicts: conflicts,
    );

    _repairRelations(people, events, localPeople, remotePeople, basePeople);
    final selectedPeople = people.values
        .where((item) => item.value != null)
        .map((item) => Person.fromJson(item.value!))
        .toList();
    final selectedEvents = events.values
        .where((item) => item.value != null)
        .map((item) => EventItem.fromJson(item.value!))
        .toList();
    final revisions = <String, Revision>{};
    for (final revision in [
      ...local.archive.revisions,
      ...remote.archive.revisions,
    ]) {
      final current = revisions[revision.id];
      if (current == null || revision.at.isAfter(current.at)) {
        revisions[revision.id] = revision;
      }
    }
    final archive = Archive(
      people: selectedPeople,
      events: selectedEvents,
      customTags: {
        ...local.archive.customTags,
        ...remote.archive.customTags,
      }.toList()..sort(),
      personTags: {
        ...local.archive.effectivePersonTags,
        ...remote.archive.effectivePersonTags,
      }.toList()..sort(),
      eventTags: {
        ...local.archive.effectiveEventTags,
        ...remote.archive.effectiveEventTags,
      }.toList()..sort(),
      revisions: revisions.values.toList()
        ..sort((left, right) => left.at.compareTo(right.at)),
    );
    final trash = _mergeTrash(
      local: local,
      remote: remote,
      selectedPeople: people,
      selectedEvents: events,
    );
    final tombstones = _mergeTombstones(local, remote, people, events);
    final retentionDays = _mergeRetention(
      local.retentionDays,
      remote.retentionDays,
      baseline?.retentionDays,
      baseline?.writtenAt,
      remote.writtenAt,
    );
    return SyncMergeResult(
      envelope: SyncEnvelope(
        archive: archive,
        trash: trash,
        tombstones: tombstones,
        retentionDays: retentionDays,
        writtenAt: remote.writtenAt.isAfter(local.writtenAt)
            ? remote.writtenAt
            : local.writtenAt,
        deviceId: remote.writtenAt.isAfter(local.writtenAt)
            ? remote.deviceId
            : local.deviceId,
      ),
      conflicts: conflicts,
    );
  }

  static Map<String, _EntityVersion> _mergeEntities({
    required EntityType type,
    required Map<String, _EntityVersion> local,
    required Map<String, _EntityVersion> remote,
    required Map<String, _EntityVersion> base,
    required Map<String, SyncConflictChoice> resolutions,
    required List<SyncConflict> conflicts,
  }) {
    final result = <String, _EntityVersion>{};
    final ids = {...local.keys, ...remote.keys, ...base.keys};
    for (final id in ids) {
      final left = local[id];
      final right = remote[id];
      final before = base[id];
      _EntityVersion? selected;
      final same = _same(left, right);
      if (same) {
        selected = left ?? right;
      } else if (before != null && _same(left, before)) {
        selected = right;
      } else if (before != null && _same(right, before)) {
        selected = left;
      } else if (left == null) {
        selected = right;
      } else if (right == null) {
        selected = left;
      } else {
        final conflict = SyncConflict(
          entityType: type,
          id: id,
          local: left.value,
          remote: right.value,
        );
        conflicts.add(conflict);
        selected = resolutions[conflict.key] == SyncConflictChoice.remote
            ? right
            : left;
      }
      if (selected != null) result[id] = selected;
    }
    return result;
  }

  static void _repairRelations(
    Map<String, _EntityVersion> people,
    Map<String, _EntityVersion> events,
    Map<String, _EntityVersion> localPeople,
    Map<String, _EntityVersion> remotePeople,
    Map<String, _EntityVersion> basePeople,
  ) {
    final peopleById = <String, Map<String, dynamic>>{};
    for (final entry in people.entries) {
      final value = entry.value.value;
      if (value != null) peopleById[entry.key] = value;
    }
    final eventsById = <String, EventItem>{};
    for (final entry in events.entries) {
      final value = entry.value.value;
      if (value != null) eventsById[entry.key] = EventItem.fromJson(value);
    }
    for (final entry in events.entries) {
      final value = entry.value.value;
      if (value == null) continue;
      final event = EventItem.fromJson(value);
      for (final link in event.people) {
        if (peopleById.containsKey(link.personId)) continue;
        final fallback =
            [
              localPeople[link.personId],
              remotePeople[link.personId],
              basePeople[link.personId],
            ].firstWhere(
              (candidate) => candidate?.value != null,
              orElse: () => null,
            );
        if (fallback?.value != null) {
          people[link.personId] = fallback!;
          peopleById[link.personId] = fallback.value!;
        }
      }
      final links = event.people
          .where((link) => peopleById.containsKey(link.personId))
          .toList();
      final predecessors = event.previousEventIds.where((id) {
        final predecessor = eventsById[id];
        return predecessor != null &&
            (predecessor.createdAt.isBefore(event.createdAt) ||
                (predecessor.createdAt.isAtSameMomentAs(event.createdAt) &&
                    predecessor.id.compareTo(event.id) < 0));
      }).toList();
      if (links.length != event.people.length ||
          predecessors.length != event.previousEventIds.length) {
        events[entry.key] = _EntityVersion(
          value: event
              .copyWith(people: links, previousEventIds: predecessors)
              .toJson(),
        );
      }
    }
  }

  static List<TrashEntry> _mergeTrash({
    required SyncEnvelope local,
    required SyncEnvelope remote,
    required Map<String, _EntityVersion> selectedPeople,
    required Map<String, _EntityVersion> selectedEvents,
  }) {
    final entries = <String, TrashEntry>{};
    for (final entry in [...local.trash, ...remote.trash]) {
      final key = '${entry.entityType.name}:${entry.id}';
      final current = entries[key];
      if (current == null || entry.deletedAt.isAfter(current.deletedAt)) {
        entries[key] = entry;
      }
    }
    entries.removeWhere((key, _) {
      final type = key.startsWith('person:')
          ? EntityType.person
          : EntityType.event;
      final id = key.substring(key.indexOf(':') + 1);
      final selected = (type == EntityType.person
          ? selectedPeople
          : selectedEvents)[id];
      return selected?.value != null;
    });
    return entries.values.toList()
      ..sort((left, right) => right.deletedAt.compareTo(left.deletedAt));
  }

  static List<SyncTombstone> _mergeTombstones(
    SyncEnvelope local,
    SyncEnvelope remote,
    Map<String, _EntityVersion> people,
    Map<String, _EntityVersion> events,
  ) {
    final result = <String, SyncTombstone>{};
    for (final tombstone in [...local.tombstones, ...remote.tombstones]) {
      final key = '${tombstone.entityType.name}:${tombstone.id}';
      final current = result[key];
      if (current == null || tombstone.deletedAt.isAfter(current.deletedAt)) {
        result[key] = tombstone;
      }
    }
    result.removeWhere((key, _) {
      final type = key.startsWith('person:')
          ? EntityType.person
          : EntityType.event;
      final id = key.substring(key.indexOf(':') + 1);
      final selected = (type == EntityType.person ? people : events)[id];
      return selected?.value != null;
    });
    return result.values.toList()
      ..sort((left, right) => right.deletedAt.compareTo(left.deletedAt));
  }

  static int _mergeRetention(
    int local,
    int remote,
    int? baseline,
    DateTime? baselineWrittenAt,
    DateTime remoteWrittenAt,
  ) {
    if (local == remote) return local;
    if (baseline == null) return remote;
    if (local == baseline) return remote;
    if (remote == baseline) return local;
    return remoteWrittenAt.isAfter(
          baselineWrittenAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        )
        ? remote
        : local;
  }

  static Map<String, _EntityVersion> _entityVersions(
    SyncEnvelope envelope,
    EntityType type,
  ) {
    final result = <String, _EntityVersion>{};
    if (type == EntityType.person) {
      for (final person in envelope.archive.people) {
        result[person.id] = _EntityVersion(value: person.toJson());
      }
    } else {
      for (final event in envelope.archive.events) {
        result[event.id] = _EntityVersion(value: event.toJson());
      }
    }
    for (final tombstone in envelope.tombstones.where(
      (item) => item.entityType == type,
    )) {
      if (!result.containsKey(tombstone.id)) {
        result[tombstone.id] = _EntityVersion(deletedAt: tombstone.deletedAt);
      }
    }
    return result;
  }

  static bool _same(_EntityVersion? left, _EntityVersion? right) {
    if (left == null || right == null) return left == null && right == null;
    if (left.value == null || right.value == null) {
      return left.value == null &&
          right.value == null &&
          left.deletedAt != null &&
          right.deletedAt != null;
    }
    return jsonEncode(left.value) == jsonEncode(right.value);
  }
}

class _EntityVersion {
  const _EntityVersion({this.value, this.deletedAt});

  final Map<String, dynamic>? value;
  final DateTime? deletedAt;
}

EntityType _entityType(Object? value) => switch (value) {
  'person' || '人物' => EntityType.person,
  'event' || '事件' => EntityType.event,
  _ => throw const FormatException('不支持的同步记录类型。'),
};

List<Map<String, dynamic>> _listOfMaps(Object? value) {
  if (value is! List) throw const FormatException('同步档案列表无效。');
  return value
      .map((item) {
        if (item is! Map) throw const FormatException('同步档案条目无效。');
        return Map<String, dynamic>.from(item);
      })
      .toList(growable: false);
}

int _retentionDays(Object? value) => switch (value) {
  0 || 7 || 30 || 90 || 180 || 365 => value as int,
  _ => 30,
};
