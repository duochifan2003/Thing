import Cocoa
import FlutterMacOS
import WidgetKit

private let widgetDefaultsSuite = "local.munch.eventatlas.widget-data"
private let recentEventsKey = "recentEvents"
private let syncAccessChannelName = "local.munch.eventatlas/sync-access"

@main
class AppDelegate: FlutterAppDelegate {
  private var syncScopedURL: URL?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      super.applicationDidFinishLaunching(notification)
      return
    }
    let channel = FlutterMethodChannel(
      name: "local.munch.eventatlas/widget",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "update", let events = (call.arguments as? [String: Any])?["events"] else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard JSONSerialization.isValidJSONObject(["events": events]),
            let data = try? JSONSerialization.data(withJSONObject: ["events": events]),
            let defaults = UserDefaults(suiteName: widgetDefaultsSuite) else {
        result(FlutterError(
          code: "widget_cache_unavailable",
          message: "无法写入小组件共享缓存。",
          details: nil
        ))
        return
      }
      defaults.set(data, forKey: recentEventsKey)
      WidgetCenter.shared.reloadTimelines(ofKind: "EventAtlasWidget")
      result(nil)
    }
    let syncAccessChannel = FlutterMethodChannel(
      name: syncAccessChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    syncAccessChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "app_unavailable", message: nil, details: nil))
        return
      }
      self.handleSyncAccess(call, result: result)
    }
    super.applicationDidFinishLaunching(notification)
  }

  private func handleSyncAccess(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createBookmark":
      guard let directory = call.arguments as? String else {
        result(FlutterError(code: "invalid_directory", message: "同步目录无效。", details: nil))
        return
      }
      let url = URL(fileURLWithPath: directory, isDirectory: true)
      do {
        let bookmark = try url.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        guard url.startAccessingSecurityScopedResource() else {
          result(FlutterError(
            code: "sync_access_denied",
            message: "无法获得同步目录访问权限。",
            details: nil
          ))
          return
        }
        syncScopedURL?.stopAccessingSecurityScopedResource()
        syncScopedURL = url
        result(bookmark.base64EncodedString())
      } catch {
        result(FlutterError(
          code: "sync_bookmark_failed",
          message: "无法保存同步目录访问权限。",
          details: error.localizedDescription
        ))
      }
    case "startBookmark":
      guard let encoded = call.arguments as? String,
            let data = Data(base64Encoded: encoded) else {
        result(FlutterError(code: "invalid_sync_bookmark", message: "同步目录授权无效。", details: nil))
        return
      }
      var isStale = false
      do {
        let url = try URL(
          resolvingBookmarkData: data,
          options: [.withSecurityScope],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )
        guard url.startAccessingSecurityScopedResource() else {
          result(FlutterError(
            code: "sync_access_denied",
            message: "无法恢复同步目录访问权限。",
            details: nil
          ))
          return
        }
        syncScopedURL?.stopAccessingSecurityScopedResource()
        syncScopedURL = url
        var refreshed = encoded
        if isStale,
           let bookmark = try? url.bookmarkData(
             options: [.withSecurityScope],
             includingResourceValuesForKeys: nil,
             relativeTo: nil
           ) {
          refreshed = bookmark.base64EncodedString()
        }
        result(["path": url.path, "bookmark": refreshed])
      } catch {
        result(FlutterError(
          code: "sync_bookmark_failed",
          message: "无法恢复同步目录访问权限。",
          details: error.localizedDescription
        ))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }
}
