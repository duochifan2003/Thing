import Foundation
import SwiftUI
import WidgetKit

private let widgetDefaultsSuite = "local.munch.eventatlas.widget-data"
private let recentEventsKey = "recentEvents"

struct ArchiveEvent: Codable, Identifiable {
  let id: String
  let title: String
  let precision: String
  let start: String
  let end: String?
  let place: String

  var dateLabel: String {
    let format: (String) -> String = { $0.replacingOccurrences(of: "-", with: ".") }
    let formattedEnd = end.flatMap { $0.isEmpty ? nil : format($0) }
    return precision == "range" ? "\(format(start)) — \(formattedEnd ?? "至今")" : format(start)
  }
}

struct EventAtlasEntry: TimelineEntry {
  enum State { case content([ArchiveEvent]), empty, unavailable }
  let date: Date
  let state: State
}

struct EventAtlasProvider: TimelineProvider {
  func placeholder(in context: Context) -> EventAtlasEntry {
    EventAtlasEntry(date: .now, state: .content([ArchiveEvent(id: "preview", title: "社区影像计划启动", precision: "day", start: "2025-04-01", end: nil, place: "北仓社区")]))
  }

  func getSnapshot(in context: Context, completion: @escaping (EventAtlasEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<EventAtlasEntry>) -> Void) {
    completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
  }

  private func entry() -> EventAtlasEntry {
    guard let events = ArchiveReader().recentEvents() else {
      return EventAtlasEntry(date: .now, state: .unavailable)
    }
    return EventAtlasEntry(date: .now, state: events.isEmpty ? .empty : .content(events))
  }
}

private struct ArchiveReader {
  func recentEvents() -> [ArchiveEvent]? {
    guard let data = UserDefaults(suiteName: widgetDefaultsSuite)?.data(forKey: recentEventsKey) else {
      return nil
    }
    return try? JSONDecoder().decode(ArchiveResponse.self, from: data).events
  }

  private struct ArchiveResponse: Codable { let events: [ArchiveEvent] }
}

struct EventAtlasWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: EventAtlasEntry

  var body: some View {
    Group {
      switch entry.state {
      case .content(let events): content(events)
      case .empty: message("还没有事件", detail: "打开事件录后新建记录")
      case .unavailable: message("无法读取档案", detail: "打开事件录后重试")
      }
    }
    .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
  }

  @ViewBuilder private func content(_ events: [ArchiveEvent]) -> some View {
    if family == .systemSmall, let event = events.first {
      VStack(alignment: .leading, spacing: 7) {
        Text("最近更新").font(.caption).foregroundStyle(.secondary)
        Text(event.dateLabel).font(.caption2).foregroundStyle(.secondary)
        Text(event.title).font(.headline).lineLimit(2)
        Spacer(minLength: 0)
        Text(event.place.isEmpty ? "未记录地点" : event.place).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text("最近更新").font(.caption).foregroundStyle(.secondary)
        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
          if index > 0, events[index - 1].dateLabel != event.dateLabel {
            Divider().padding(.leading, 76)
          }
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(event.dateLabel)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .frame(width: 68, alignment: .leading)
              .lineLimit(1)
            VStack(alignment: .leading, spacing: 1) {
              Text(event.title).font(.subheadline.weight(.medium)).lineLimit(1)
              Text(event.place.isEmpty ? "未记录地点" : event.place).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
          }
        }
        Spacer(minLength: 0)
      }
    }
  }

  private func message(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("事件录").font(.caption).foregroundStyle(.secondary)
      Text(title).font(.headline)
      Text(detail).font(.caption).foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
  }
}

struct EventAtlasWidget: Widget {
  let kind = "EventAtlasWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: EventAtlasProvider()) { EventAtlasWidgetView(entry: $0) }
      .configurationDisplayName("最近更新")
      .description("显示最近编辑的事件记录。")
      .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@main struct EventAtlasWidgetBundle: WidgetBundle { var body: some Widget { EventAtlasWidget() } }
