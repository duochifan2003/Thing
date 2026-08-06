import Foundation
import SwiftUI
import WidgetKit

private let widgetDefaultsSuite = "local.munch.eventatlas.widget-data"
private let recentEventsKey = "recentEvents"

enum WidgetPalette: String {
  case berryRedOat
  case royalBlueYellow

  init(_ value: String?) {
    self = WidgetPalette(rawValue: value ?? "") ?? .berryRedOat
  }

  var primary: Color {
    switch self {
    case .berryRedOat: return Color(red: 181 / 255, green: 0, blue: 49 / 255)
    case .royalBlueYellow: return Color(red: 1 / 255, green: 43 / 255, blue: 172 / 255)
    }
  }

  var companion: Color {
    switch self {
    case .berryRedOat: return Color(red: 224 / 255, green: 209 / 255, blue: 189 / 255)
    case .royalBlueYellow: return Color(red: 1, green: 207 / 255, blue: 0)
    }
  }

  var ink: Color { .black }
  var muted: Color { .black.opacity(0.62) }
  var error: Color { Color(red: 181 / 255, green: 0, blue: 49 / 255) }
}

struct ArchiveEvent: Codable, Identifiable {
  let id: String
  let title: String
  let precision: String
  let start: String
  let end: String?
  let place: String
  let description: String?
  let status: String?
  let tags: [String]?

  var dateLabel: String {
    guard !start.isEmpty else { return "待定" }
    let format: (String) -> String = { $0.replacingOccurrences(of: "-", with: ".") }
    let formattedEnd = end.flatMap { $0.isEmpty ? nil : format($0) }
    return precision == "range" ? "\(format(start)) — \(formattedEnd ?? "至今")" : format(start)
  }

  var widgetDateLabel: String {
    guard !start.isEmpty else { return "待定" }
    let formattedStart = start.replacingOccurrences(of: "-", with: ".")
    return precision == "range" ? "\(formattedStart)—" : formattedStart
  }

  var widgetPlaceLabel: String? {
    let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let parts = trimmed
      .split(separator: "·")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    guard parts.first == "中国" else { return trimmed }
    let administrativeParts = Array(parts.dropFirst())
    guard !administrativeParts.isEmpty else { return trimmed }
    if administrativeParts.count >= 3 {
      return administrativeParts.dropFirst().prefix(2).joined(separator: " · ")
    }
    return administrativeParts.suffix(2).joined(separator: " · ")
  }

  var widgetDescription: String? {
    guard let description = description?.trimmingCharacters(in: .whitespacesAndNewlines),
          !description.isEmpty else { return nil }
    return description
  }

  var widgetTagLabel: String? {
    let labels = (tags ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !labels.isEmpty else { return nil }
    return labels.prefix(2).joined(separator: " · ")
  }

  var statusLabel: String {
    switch status {
    case "scheduled": return "预定"
    case "active": return "进行中"
    case "completed": return "已结束"
    case "cancelled": return "已取消"
    default: return "事件"
    }
  }

  func statusColor(for palette: WidgetPalette) -> Color {
    switch status {
    case "scheduled", "active": return palette.primary
    case "completed": return palette.muted
    case "cancelled": return palette.error
    default: return palette.primary
    }
  }
}

struct EventAtlasEntry: TimelineEntry {
  enum State { case content([ArchiveEvent]), empty, unavailable }
  let date: Date
  let state: State
  let primaryColor: String
}

struct EventAtlasProvider: TimelineProvider {
  func placeholder(in context: Context) -> EventAtlasEntry {
    EventAtlasEntry(date: .now, state: .content([
      ArchiveEvent(id: "preview-1", title: "社区影像计划启动", precision: "day", start: "2025-04-01", end: nil, place: "北仓社区", description: "整理社区老照片与口述史，建立可持续更新的影像档案。", status: "active", tags: ["社区", "影像"]),
      ArchiveEvent(id: "preview-2", title: "口述史访谈", precision: "day", start: "2025-03-28", end: nil, place: "厦门市 · 海沧区", description: nil, status: "completed", tags: ["访谈"]),
      ArchiveEvent(id: "preview-3", title: "城市散步采集", precision: "day", start: "2025-03-18", end: nil, place: "厦门市 · 思明区", description: nil, status: "completed", tags: ["城市"]),
      ArchiveEvent(id: "preview-4", title: "档案整理工作坊", precision: "day", start: "2025-03-11", end: nil, place: "厦门市 · 集美区", description: nil, status: "scheduled", tags: ["工作坊"]),
      ArchiveEvent(id: "preview-5", title: "旧城照片征集", precision: "day", start: "2025-03-04", end: nil, place: "厦门市 · 湖里区", description: nil, status: "cancelled", tags: ["征集"]),
      ArchiveEvent(id: "preview-6", title: "展览布置完成", precision: "day", start: "2025-02-26", end: nil, place: "厦门市", description: nil, status: "completed", tags: ["展览"]),
    ]), primaryColor: WidgetPalette.berryRedOat.rawValue)
  }

  func getSnapshot(in context: Context, completion: @escaping (EventAtlasEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<EventAtlasEntry>) -> Void) {
    completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
  }

  private func entry() -> EventAtlasEntry {
    guard let data = ArchiveReader().widgetData() else {
      return EventAtlasEntry(
        date: .now,
        state: .unavailable,
        primaryColor: WidgetPalette.berryRedOat.rawValue
      )
    }
    return EventAtlasEntry(
      date: .now,
      state: data.events.isEmpty ? .empty : .content(data.events),
      primaryColor: data.primaryColor ?? WidgetPalette.berryRedOat.rawValue
    )
  }
}

private struct ArchiveReader {
  struct WidgetData: Codable {
    let events: [ArchiveEvent]
    let primaryColor: String?
  }

  func widgetData() -> WidgetData? {
    guard let data = UserDefaults(suiteName: widgetDefaultsSuite)?.data(forKey: recentEventsKey) else {
      return nil
    }
    guard let response = try? JSONDecoder().decode(WidgetData.self, from: data) else {
      return nil
    }
    return WidgetData(
      events: response.events,
      primaryColor: response.primaryColor
    )
  }
}

struct EventAtlasWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: EventAtlasEntry

  var body: some View {
    Group {
      switch entry.state {
      case .content(let events): content(events)
      case .empty: message("还没有事件", detail: "打开 Thing 后新建记录")
      case .unavailable: message("无法读取档案", detail: "打开 Thing 后重试")
      }
    }
    .padding(contentInsets)
    .foregroundStyle(palette.ink)
    .containerBackground(for: .widget) { palette.companion }
  }

  private var palette: WidgetPalette { WidgetPalette(entry.primaryColor) }

  private var contentInsets: EdgeInsets {
    if family == .systemLarge {
      return EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20)
    }
    return family == .systemMedium
      ? EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
      : EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
  }

  private var todayLabel: String {
    let date = Calendar.current.dateComponents([.year, .month, .day], from: entry.date)
    return String(format: "%04d.%02d.%02d", date.year ?? 0, date.month ?? 0, date.day ?? 0)
  }

  @ViewBuilder private func content(_ events: [ArchiveEvent]) -> some View {
    if family == .systemSmall, let event = events.first {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Text("Thing")
            .font(.system(size: 12, weight: .bold))
          Spacer(minLength: 0)
          Circle().fill(palette.primary).frame(width: 6, height: 6)
        }
        Spacer(minLength: 2)
        Text(event.dateLabel)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(palette.primary)
          .lineLimit(1)
        Text(event.title)
          .font(.system(size: 17, weight: .bold))
          .lineLimit(2)
        Spacer(minLength: 0)
        if !event.place.isEmpty {
          Text(event.place)
            .font(.system(size: 10))
            .foregroundStyle(palette.muted)
            .lineLimit(1)
        }
      }
    } else if family == .systemLarge {
      largeContent(events)
    } else {
      let visibleEvents = Array(events.prefix(3))

      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text("Thing")
            .font(.system(size: 14, weight: .semibold))
          Spacer(minLength: 0)
          Text("今天 · \(todayLabel) · \(visibleEvents.count) 条")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(palette.muted)
        }
        .frame(height: 20)

        if !visibleEvents.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(visibleEvents) { event in
              mediumEventRow(event)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  @ViewBuilder private func largeContent(_ events: [ArchiveEvent]) -> some View {
    if let featuredEvent = events.first {
      let recentEvents = Array(events.dropFirst().prefix(5))

      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text("Thing")
            .font(.system(size: 16, weight: .bold))
          Spacer(minLength: 0)
          Text("今天 · \(todayLabel) · \(events.count) 条")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.muted)
        }

        featuredEventCard(featuredEvent)

        if !recentEvents.isEmpty {
          Text("其他最近更新")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.muted)

          VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(recentEvents.enumerated()), id: \.element.id) { item in
              largeEventRow(item.element)
              if item.offset < recentEvents.count - 1 {
                Divider().padding(.leading, 82)
              }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      message("还没有事件", detail: "打开 Thing 后新建记录")
    }
  }

  private func featuredEventCard(_ event: ArchiveEvent) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .center) {
        statusPill(event)
        Spacer(minLength: 8)
        Text(event.dateLabel)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(palette.primary)
          .lineLimit(1)
      }

      Text(event.title)
        .font(.system(size: 18, weight: .bold))
        .lineLimit(2)

      if let description = event.widgetDescription {
        Text(description)
          .font(.system(size: 11.5))
          .foregroundStyle(palette.muted)
          .lineLimit(2)
      }

      let details = [event.widgetPlaceLabel, event.widgetTagLabel].compactMap { $0 }.joined(separator: " · ")
      if !details.isEmpty {
        Text(details)
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(palette.muted)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(palette.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func mediumEventRow(_ event: ArchiveEvent) -> some View {
    HStack(alignment: .center, spacing: 14) {
      dateBadge(event)
      VStack(alignment: .leading, spacing: 2) {
        Text(event.title)
          .font(.system(size: 13, weight: .medium))
          .lineLimit(1)
        if let place = event.widgetPlaceLabel {
          Text(place)
            .font(.system(size: 10.5))
            .foregroundStyle(palette.muted)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: 32, alignment: .top)
  }

  private func largeEventRow(_ event: ArchiveEvent) -> some View {
    HStack(alignment: .top, spacing: 14) {
      dateBadge(event)
        .padding(.top, 3)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 8) {
          Text(event.title)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
          Spacer(minLength: 0)
          statusPill(event)
        }
        let details = [event.widgetPlaceLabel, event.widgetTagLabel].compactMap { $0 }.joined(separator: " · ")
        if !details.isEmpty {
          Text(details)
            .font(.system(size: 11))
            .foregroundStyle(palette.muted)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 7)
  }

  private func statusPill(_ event: ArchiveEvent) -> some View {
    Text(event.statusLabel)
      .font(.system(size: 9.5, weight: .semibold))
      .foregroundStyle(event.statusColor(for: palette))
      .lineLimit(1)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(event.statusColor(for: palette).opacity(0.12), in: Capsule())
  }

  private func dateBadge(_ event: ArchiveEvent) -> some View {
    Text(event.widgetDateLabel)
      .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
      .foregroundStyle(palette.primary)
      .lineLimit(1)
      .minimumScaleFactor(0.85)
      .frame(width: 68, height: 18, alignment: .center)
      .background(palette.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
  }

  private func message(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Thing")
        .font(.system(size: 12, weight: .bold))
      Spacer(minLength: 0)
      HStack(alignment: .top, spacing: 9) {
        Circle().fill(palette.primary).frame(width: 8, height: 8).padding(.top, 5)
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.system(size: 15, weight: .bold))
          Text(detail)
            .font(.system(size: 10))
            .foregroundStyle(palette.muted)
        }
      }
      Spacer(minLength: 0)
    }
  }
}

struct EventAtlasWidget: Widget {
  let kind = "EventAtlasWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: EventAtlasProvider()) { EventAtlasWidgetView(entry: $0) }
      .configurationDisplayName("最近更新")
      .description("显示最近编辑的事件记录；大组件会展示一条详细事件和五条近期记录。")
      .contentMarginsDisabled()
      .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@main struct EventAtlasWidgetBundle: WidgetBundle { var body: some Widget { EventAtlasWidget() } }
