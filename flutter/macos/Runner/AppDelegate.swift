import Cocoa
import Darwin
import FlutterMacOS
import WidgetKit

@main
class AppDelegate: FlutterAppDelegate {
  private let widgetServer = WidgetServer()

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      super.applicationDidFinishLaunching(notification)
      return
    }
    let channel = FlutterMethodChannel(
      name: "local.munch.eventatlas/widget",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let events = (call.arguments as? [String: Any])?["events"] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.widgetServer.update(events: events)
      WidgetCenter.shared.reloadTimelines(ofKind: "EventAtlasWidget")
      result(nil)
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }
}

private final class WidgetServer {
  private static let port: UInt16 = 48127
  private let queue = DispatchQueue(label: "local.munch.eventatlas.widget-server")
  private let lock = NSLock()
  private var socket: Int32 = -1
  private var payload = Data("{\"events\":[]}".utf8)

  init() {
    socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard socket >= 0 else { return }
    var reuseAddress: Int32 = 1
    setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_in(
      sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
      sin_family: sa_family_t(AF_INET),
      sin_port: Self.port.bigEndian,
      sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
      sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
    )
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0, listen(socket, SOMAXCONN) == 0 else {
      close(socket)
      socket = -1
      return
    }
    queue.async { [weak self] in self?.acceptConnections() }
  }

  func update(events: Any) {
    guard JSONSerialization.isValidJSONObject(["events": events]),
          let data = try? JSONSerialization.data(withJSONObject: ["events": events]) else {
      return
    }
    lock.lock()
    payload = data
    lock.unlock()
  }

  private func acceptConnections() {
    while socket >= 0 {
      let connection = accept(socket, nil, nil)
      guard connection >= 0 else { continue }
      defer { close(connection) }
      var request = [UInt8](repeating: 0, count: 4096)
      _ = recv(connection, &request, request.count, 0)
      lock.lock()
      let body = payload
      lock.unlock()
      let headers = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
      let response = Data(headers.utf8) + body
      response.withUnsafeBytes { buffer in
        guard let baseAddress = buffer.baseAddress else { return }
        _ = send(connection, baseAddress, buffer.count, 0)
      }
    }
  }

  deinit { if socket >= 0 { close(socket) } }
}
