import 'dart:convert';

enum Precision { year, month, day, range }

enum Role { organizer, participant }

enum EventStatus { scheduled, active, completed, cancelled }

enum EntityType { person, event }

enum RevisionAction { create, update }

extension PrecisionLabel on Precision {
  String get label => switch (this) {
    Precision.year => '年份',
    Precision.month => '月份',
    Precision.day => '具体日期',
    Precision.range => '起止区间',
  };
}

extension RoleLabel on Role {
  String get label => switch (this) {
    Role.organizer => '组织者',
    Role.participant => '参与者',
  };
}

extension EventStatusLabel on EventStatus {
  String get label => switch (this) {
    EventStatus.scheduled => '预定',
    EventStatus.active => '进行中',
    EventStatus.completed => '已结束',
    EventStatus.cancelled => '已取消',
  };
}

extension EntityTypeLabel on EntityType {
  String get label => this == EntityType.person ? '人物' : '事件';
}

extension RevisionActionLabel on RevisionAction {
  String get label => this == RevisionAction.create ? '创建' : '更新';
}

class Person {
  const Person({
    required this.id,
    required this.name,
    required this.bio,
    required this.tags,
    required this.notes,
    required this.sources,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String bio;
  final List<String> tags;
  final String notes;
  final List<String> sources;
  final DateTime createdAt;
  final DateTime updatedAt;

  Person copyWith({
    String? name,
    String? bio,
    List<String>? tags,
    String? notes,
    List<String>? sources,
    DateTime? updatedAt,
  }) => Person(
    id: id,
    name: name ?? this.name,
    bio: bio ?? this.bio,
    tags: tags ?? this.tags,
    notes: notes ?? this.notes,
    sources: sources ?? this.sources,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bio': bio,
    'tags': tags,
    'notes': notes,
    'sources': sources,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['id'] as String,
    name: json['name'] as String,
    bio: json['bio'] as String? ?? '',
    tags: (json['tags'] as List? ?? []).cast<String>(),
    notes: json['notes'] as String? ?? '',
    sources: (json['sources'] as List? ?? []).cast<String>(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

class PersonLink {
  const PersonLink({required this.personId, required this.role});

  final String personId;
  final Role role;

  Map<String, dynamic> toJson() => {'personId': personId, 'role': role.label};

  factory PersonLink.fromJson(Map<String, dynamic> json) => PersonLink(
    personId: json['personId'] as String,
    role: _roleFromJson(json['role'] as String),
  );
}

Role _roleFromJson(String value) => switch (value) {
  '组织者' || 'organizer' || '当事人' || 'subject' => Role.organizer,
  '参与者' ||
  'participant' ||
  '见证人' ||
  'witness' ||
  '提及者' ||
  'mentioned' => Role.participant,
  _ => throw FormatException('不支持的人物角色：$value'),
};

class EventItem {
  const EventItem({
    required this.id,
    required this.title,
    required this.precision,
    required this.start,
    this.end,
    required this.place,
    required this.description,
    required this.tags,
    required this.sources,
    required this.people,
    required this.createdAt,
    required this.updatedAt,
    this.status = EventStatus.completed,
    this.previousEventIds = const [],
    this.images = const [],
  });

  final String id;
  final String title;
  final Precision precision;
  final String start;
  final String? end;
  final String place;
  final String description;
  final List<String> tags;
  final List<String> sources;
  final List<PersonLink> people;
  final DateTime createdAt;
  final DateTime updatedAt;
  final EventStatus status;
  final List<String> previousEventIds;

  /// Base64-encoded image bytes. Local file paths are intentionally not stored.
  final List<String> images;

  String get dateLabel {
    if (start.isEmpty) return '待定';
    String format(String value) => value.replaceAll('-', '.');
    return precision == Precision.range
        ? '${format(start)} — ${end == null || end!.isEmpty ? '至今' : format(end!)}'
        : format(start);
  }

  EventItem copyWith({
    String? title,
    Precision? precision,
    String? start,
    String? end,
    bool clearEnd = false,
    String? place,
    String? description,
    List<String>? tags,
    List<String>? sources,
    List<PersonLink>? people,
    DateTime? updatedAt,
    EventStatus? status,
    List<String>? previousEventIds,
    List<String>? images,
  }) => EventItem(
    id: id,
    title: title ?? this.title,
    precision: precision ?? this.precision,
    start: start ?? this.start,
    end: clearEnd ? null : end ?? this.end,
    place: place ?? this.place,
    description: description ?? this.description,
    tags: tags ?? this.tags,
    sources: sources ?? this.sources,
    people: people ?? this.people,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    status: status ?? this.status,
    previousEventIds: previousEventIds ?? this.previousEventIds,
    images: images ?? this.images,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'precision': precision.name,
    'start': start,
    'end': end,
    'place': place,
    'description': description,
    'tags': tags,
    'sources': sources,
    'people': people.map((link) => link.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'status': status.name,
    'previousEventIds': previousEventIds,
    'images': images,
  };

  factory EventItem.fromJson(Map<String, dynamic> json) => EventItem(
    id: json['id'] as String,
    title: json['title'] as String,
    precision: Precision.values.byName(json['precision'] as String),
    start: json['start'] as String,
    end: json['end'] as String?,
    place: json['place'] as String? ?? '',
    description: json['description'] as String? ?? '',
    tags: (json['tags'] as List? ?? []).cast<String>(),
    sources: (json['sources'] as List? ?? []).cast<String>(),
    people: (json['people'] as List? ?? [])
        .map(
          (item) => PersonLink.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    status: _eventStatusFromJson(json['status'] as String? ?? 'completed'),
    previousEventIds: (json['previousEventIds'] as List? ?? []).cast<String>(),
    images: (json['images'] as List? ?? []).cast<String>(),
  );
}

EventStatus _eventStatusFromJson(String value) => switch (value) {
  '预定' || 'scheduled' => EventStatus.scheduled,
  '进行中' || 'active' => EventStatus.active,
  '已结束' || 'completed' => EventStatus.completed,
  '已取消' || 'cancelled' || 'canceled' => EventStatus.cancelled,
  _ => throw FormatException('不支持的事件状态：$value'),
};

class ArchiveChange {
  const ArchiveChange({
    required this.field,
    required this.before,
    required this.after,
  });

  final String field;
  final String before;
  final String after;

  Map<String, dynamic> toJson() => {
    'field': field,
    'before': before,
    'after': after,
  };

  factory ArchiveChange.fromJson(Map<String, dynamic> json) => ArchiveChange(
    field: json['field'] as String,
    before: json['before'] as String? ?? '—',
    after: json['after'] as String? ?? '—',
  );
}

class Revision {
  const Revision({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.at,
    required this.changes,
  });

  final String id;
  final EntityType entityType;
  final String entityId;
  final RevisionAction action;
  final DateTime at;
  final List<ArchiveChange> changes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityType': entityType.label,
    'entityId': entityId,
    'action': action.label,
    'at': at.toIso8601String(),
    'changes': changes.map((change) => change.toJson()).toList(),
  };

  factory Revision.fromJson(Map<String, dynamic> json) => Revision(
    id: json['id'] as String,
    entityType: _entityTypeFromJson(json['entityType'] as String),
    entityId: json['entityId'] as String,
    action: _revisionActionFromJson(json['action'] as String),
    at: DateTime.parse(json['at'] as String),
    changes: (json['changes'] as List? ?? [])
        .map(
          (item) =>
              ArchiveChange.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );
}

EntityType _entityTypeFromJson(String value) => switch (value) {
  '人物' || 'person' => EntityType.person,
  '事件' || 'event' => EntityType.event,
  _ => throw FormatException('不支持的修订类型：$value'),
};

RevisionAction _revisionActionFromJson(String value) => switch (value) {
  '创建' || 'create' => RevisionAction.create,
  '更新' || 'update' => RevisionAction.update,
  _ => throw FormatException('不支持的修订动作：$value'),
};

class Archive {
  const Archive({
    required this.people,
    required this.events,
    this.customTags = const [],
    this.personTags = const [],
    this.eventTags = const [],
    this.revisions = const [],
  });

  final List<Person> people;
  final List<EventItem> events;

  /// Legacy v2 catalog kept for older importers and databases.
  final List<String> customTags;
  final List<String> personTags;
  final List<String> eventTags;
  final List<Revision> revisions;

  List<String> get effectivePersonTags =>
      personTags.isEmpty && eventTags.isEmpty ? customTags : personTags;

  List<String> get effectiveEventTags =>
      personTags.isEmpty && eventTags.isEmpty ? customTags : eventTags;

  List<String> get allTagCatalog =>
      {...effectivePersonTags, ...effectiveEventTags}.toList();

  Archive copyWith({
    List<Person>? people,
    List<EventItem>? events,
    List<String>? customTags,
    List<String>? personTags,
    List<String>? eventTags,
    List<Revision>? revisions,
  }) => Archive(
    people: people ?? this.people,
    events: events ?? this.events,
    customTags: customTags ?? this.customTags,
    personTags: personTags ?? this.personTags,
    eventTags: eventTags ?? this.eventTags,
    revisions: revisions ?? this.revisions,
  );

  Map<String, dynamic> toJson() => {
    'version': 2,
    'people': people.map((person) => person.toJson()).toList(),
    'events': events.map((event) => event.toJson()).toList(),
    'customTags': allTagCatalog,
    'personTags': effectivePersonTags,
    'eventTags': effectiveEventTags,
    'revisions': revisions.map((revision) => revision.toJson()).toList(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory Archive.decode(String source) {
    final json = Map<String, dynamic>.from(jsonDecode(source) as Map);
    if (json['version'] != 1 && json['version'] != 2) {
      throw const FormatException('不支持的档案版本。');
    }
    final legacyTags = _archiveTags(json['customTags']);
    return Archive(
      people: (json['people'] as List)
          .map(
            (item) => Person.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      events: (json['events'] as List)
          .map(
            (item) =>
                EventItem.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      customTags: legacyTags,
      personTags: json.containsKey('personTags')
          ? _archiveTags(json['personTags'])
          : legacyTags,
      eventTags: json.containsKey('eventTags')
          ? _archiveTags(json['eventTags'])
          : legacyTags,
      revisions: (json['revisions'] as List? ?? [])
          .map(
            (item) => Revision.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }
}

List<String> _archiveTags(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];
