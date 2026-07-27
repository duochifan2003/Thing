import Foundation

enum ArchiveStoreError: LocalizedError {
  case unavailableContainer
  case unsupportedVersion

  var errorDescription: String? {
    switch self {
    case .unavailableContainer: return "无法访问共享档案库。"
    case .unsupportedVersion: return "档案格式版本不受支持。"
    }
  }
}

struct ArchiveStore: Codable {
  let version: Int
  let people: [ArchivePerson]
  let events: [ArchiveEvent]
  let revisions: [ArchiveRevision]
}

struct ArchivePerson: Codable, Identifiable {
  let id: String
  let name: String
  let bio: String
  let tags: [String]
  let notes: String
  let sources: [String]
  let createdAt: String
  let updatedAt: String
}

struct ArchiveEvent: Codable, Identifiable, Hashable {
  let id: String
  let title: String
  let precision: String
  let start: String
  let end: String?
  let place: String
  let description: String
  let tags: [String]
  let sources: [String]
  let people: [ArchiveEventPerson]
  let createdAt: String
  let updatedAt: String

  var displayDate: String {
    let date = start.replacingOccurrences(of: "-", with: ".")
    guard precision == "range" else { return date }
    return "\(date) — \((end ?? "至今").replacingOccurrences(of: "-", with: "."))"
  }
}

struct ArchiveEventPerson: Codable, Hashable {
  let personId: String
  let role: String
}

struct ArchiveRevision: Codable {
  let id: String
  let entityType: String
  let entityId: String
  let action: String
  let at: String
  let changes: [ArchiveChange]
}

struct ArchiveChange: Codable {
  let field: String
  let before: String
  let after: String
}

struct ArchiveRepository {
  static let appGroupIdentifier = "group.local.munch.person-event-atlas"
  private let fileURL: URL

  init(containerURL: URL? = nil, fileManager: FileManager = .default) throws {
    guard let container = containerURL ?? fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) else {
      throw ArchiveStoreError.unavailableContainer
    }
    let directory = container.appendingPathComponent("Archive", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    fileURL = directory.appendingPathComponent("archive-v1.json")
  }

  func load() throws -> ArchiveStore? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    let archive = try JSONDecoder().decode(ArchiveStore.self, from: Data(contentsOf: fileURL))
    guard archive.version == 1 else { throw ArchiveStoreError.unsupportedVersion }
    return archive
  }

  func write(_ archive: ArchiveStore) throws {
    guard archive.version == 1 else { throw ArchiveStoreError.unsupportedVersion }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(archive).write(to: fileURL, options: .atomic)
  }

  func recentEvents(limit: Int = 3) throws -> [ArchiveEvent] {
    try load()?.events.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit).map { $0 } ?? []
  }
}

enum ArchiveCoding {
  static func decode(_ object: Any) throws -> ArchiveStore {
    let data = try JSONSerialization.data(withJSONObject: object)
    let archive = try JSONDecoder().decode(ArchiveStore.self, from: data)
    guard archive.version == 1 else { throw ArchiveStoreError.unsupportedVersion }
    return archive
  }

  static func object(_ archive: ArchiveStore) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(archive))
  }
}
