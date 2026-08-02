import 'package:person_event_atlas/archive.dart';

final seedArchive = Archive(
  people: [
    Person(
      id: 'p-lin',
      name: '林岚',
      bio: '独立策展人与写作者，长期关注城市记忆。',
      tags: ['文化', '上海'],
      notes: '虚构示例人物。',
      sources: ['访谈笔记 · 2025'],
      createdAt: DateTime(2025, 2, 14, 8),
      updatedAt: DateTime(2025, 2, 14, 8),
    ),
    Person(
      id: 'p-zhou',
      name: '周一川',
      bio: '建筑师，参与旧街区更新项目。',
      tags: ['建筑', '社区'],
      notes: '',
      sources: ['项目档案'],
      createdAt: DateTime(2025, 3, 1, 8),
      updatedAt: DateTime(2025, 3, 1, 8),
    ),
  ],
  events: [
    EventItem(
      id: 'e-1',
      title: '旧城散步与首次访谈',
      precision: Precision.day,
      start: '2025-03-18',
      place: '南岸街区',
      description: '围绕老店、迁徙与空间记忆进行的步行访谈。',
      tags: ['访谈', '城市记忆'],
      sources: ['现场笔记'],
      people: [PersonLink(personId: 'p-lin', role: Role.organizer)],
      createdAt: DateTime(2025, 3, 18, 10),
      updatedAt: DateTime(2025, 3, 18, 10),
    ),
    EventItem(
      id: 'e-2',
      title: '社区影像计划启动',
      precision: Precision.range,
      start: '2025-04-01',
      end: '2025-05-20',
      place: '北仓社区',
      description: '居民共同整理影像与故事的长期计划。',
      tags: ['影像', '社区'],
      sources: ['项目说明'],
      people: [
        PersonLink(personId: 'p-lin', role: Role.participant),
        PersonLink(personId: 'p-zhou', role: Role.organizer),
      ],
      createdAt: DateTime(2025, 4, 1, 8),
      updatedAt: DateTime(2025, 4, 1, 8),
    ),
  ],
  revisions: const [],
);
