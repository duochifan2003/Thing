import XCTest

final class SharedArchiveStoreTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: directory)
  }

  func testRecentEventsSortsByUpdateAndLimitsToThree() throws {
    let repository = try ArchiveRepository(containerURL: directory)
    try repository.write(ArchiveStore(version: 1, people: [], events: [event("1", "2025-01-01T00:00:00Z"), event("3", "2025-03-01T00:00:00Z"), event("2", "2025-02-01T00:00:00Z"), event("4", "2025-04-01T00:00:00Z")], revisions: []))
    XCTAssertEqual(try repository.recentEvents().map(\.id), ["4", "3", "2"])
  }

  func testRejectedWriteLeavesPreviousArchiveIntact() throws {
    let repository = try ArchiveRepository(containerURL: directory)
    let original = ArchiveStore(version: 1, people: [], events: [event("stable", "2025-01-01T00:00:00Z")], revisions: [])
    try repository.write(original)
    XCTAssertThrowsError(try repository.write(ArchiveStore(version: 2, people: [], events: [], revisions: [])))
    XCTAssertEqual(try repository.load()?.events.map(\.id), ["stable"])
  }

  private func event(_ id: String, _ updatedAt: String) -> ArchiveEvent {
    ArchiveEvent(id: id, title: id, precision: "day", start: "2025-01-01", end: nil, place: "", description: "", tags: [], sources: [], people: [], createdAt: updatedAt, updatedAt: updatedAt)
  }
}
