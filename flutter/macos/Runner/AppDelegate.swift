import Cocoa
import FlutterMacOS
import WidgetKit

private let widgetDefaultsSuite = "local.munch.eventatlas.widget-data"
private let recentEventsKey = "recentEvents"

@main
class AppDelegate: FlutterAppDelegate {
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
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }
}
