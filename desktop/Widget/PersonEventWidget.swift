import SwiftUI
import WidgetKit

struct PersonEventEntry: TimelineEntry {
  enum State { case content([ArchiveEvent]), empty, unavailable }
  let date: Date
  let state: State
}

struct PersonEventProvider: TimelineProvider {
  func placeholder(in context: Context) -> PersonEventEntry {
    PersonEventEntry(date: .now, state: .content([previewEvent]))
  }

  func getSnapshot(in context: Context, completion: @escaping (PersonEventEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PersonEventEntry>) -> Void) {
    completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
  }

  private func entry() -> PersonEventEntry {
    do {
      let events = try ArchiveRepository().recentEvents()
      return PersonEventEntry(date: .now, state: events.isEmpty ? .empty : .content(events))
    } catch {
      return PersonEventEntry(date: .now, state: .unavailable)
    }
  }
}

struct PersonEventWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: PersonEventEntry

  var body: some View {
    Group {
      switch entry.state {
      case .content(let events): content(events)
      case .empty: message("还没有事件", detail: "在人物事件库中新建记录")
      case .unavailable: message("无法读取档案", detail: "打开人物事件库后重试")
      }
    }
    .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
  }

  @ViewBuilder private func content(_ events: [ArchiveEvent]) -> some View {
    if family == .systemSmall, let event = events.first {
      Link(destination: destination(for: event)) {
        VStack(alignment: .leading, spacing: 7) {
          Text("最近更新").font(.caption).foregroundStyle(.secondary)
          Text(event.displayDate).font(.caption2).foregroundStyle(.secondary)
          Text(event.title).font(.headline).lineLimit(2)
          Spacer(minLength: 0)
          Text(event.place.isEmpty ? "未记录地点" : event.place).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
      }
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text("最近更新").font(.caption).foregroundStyle(.secondary)
        ForEach(events.prefix(3)) { event in
          Link(destination: destination(for: event)) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(event.displayDate).font(.caption2).foregroundStyle(.secondary).frame(width: 68, alignment: .leading).lineLimit(1)
              VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(event.place.isEmpty ? "未记录地点" : event.place).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
              }
            }
          }
        }
        Spacer(minLength: 0)
      }
    }
  }

  private func message(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("人物事件库").font(.caption).foregroundStyle(.secondary)
      Text(title).font(.headline)
      Text(detail).font(.caption).foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
  }

  private func destination(for event: ArchiveEvent) -> URL {
    URL(string: "person-event-atlas://event/\(event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.id)")!
  }
}

struct PersonEventWidget: Widget {
  let kind = "PersonEventWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: PersonEventProvider()) { PersonEventWidgetView(entry: $0) }
      .configurationDisplayName("最近更新")
      .description("显示最近编辑的人物事件记录。")
      .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@main struct PersonEventWidgetBundle: WidgetBundle {
  var body: some Widget { PersonEventWidget() }
}

private let previewEvent = ArchiveEvent(id: "preview", title: "社区影像计划启动", precision: "day", start: "2025-04-01", end: nil, place: "北仓社区", description: "", tags: [], sources: [], people: [], createdAt: "2025-04-01T08:00:00Z", updatedAt: "2025-04-01T08:00:00Z")
