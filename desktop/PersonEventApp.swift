import Cocoa
import WebKit
import WidgetKit

final class DialogDelegate: NSObject, WKUIDelegate {
  func webView(_: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame _: WKFrameInfo, completionHandler: @escaping () -> Void) {
    let alert = NSAlert()
    alert.messageText = message
    alert.addButton(withTitle: "确定")
    alert.runModal()
    completionHandler()
  }

  func webView(_: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame _: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
    let alert = NSAlert()
    alert.messageText = message
    alert.addButton(withTitle: "确定")
    alert.addButton(withTitle: "取消")
    completionHandler(alert.runModal() == .alertFirstButtonReturn)
  }
}

final class ArchiveBridge: NSObject, WKScriptMessageHandlerWithReply {
  private let repository: ArchiveRepository

  init(repository: ArchiveRepository) { self.repository = repository }

  func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
    guard let body = message.body as? [String: Any], let action = body["action"] as? String else {
      replyHandler(["ok": false, "error": "无效的档案请求"], nil)
      return
    }
    do {
      switch action {
      case "read":
        if let archive = try repository.load() {
          replyHandler(["ok": true, "exists": true, "value": try ArchiveCoding.object(archive)], nil)
        } else {
          replyHandler(["ok": true, "exists": false], nil)
        }
      case "write", "migrate":
        guard let value = body["value"] else { throw ArchiveStoreError.unsupportedVersion }
        try repository.write(ArchiveCoding.decode(value))
        WidgetCenter.shared.reloadTimelines(ofKind: "PersonEventWidget")
        replyHandler(["ok": true], nil)
      default:
        replyHandler(["ok": false, "error": "不支持的档案请求"], nil)
      }
    } catch {
      replyHandler(["ok": false, "error": error.localizedDescription], nil)
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKDownloadDelegate {
  private let dialogs = DialogDelegate()
  private var server: Process?
  private var window: NSWindow?
  private var webView: WKWebView?
  private var pendingEventID: String?
  private var archiveBridge: ArchiveBridge?

  func applicationDidFinishLaunching(_: Notification) {
    NSApp.setActivationPolicy(.regular)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "人物事件库"
    window.center()

    let configuration = WKWebViewConfiguration()
    do {
      let bridge = ArchiveBridge(repository: try ArchiveRepository())
      configuration.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "archiveStore")
      archiveBridge = bridge
    } catch {
      configuration.userContentController.removeAllScriptMessageHandlers()
    }

    let web = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
    web.uiDelegate = dialogs
    web.navigationDelegate = self
    web.autoresizingMask = [.width, .height]
    window.contentView?.addSubview(web)
    self.window = window
    webView = web
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    startWebApp(in: web)
  }

  func applicationWillTerminate(_: Notification) {
    if server?.isRunning == true { server?.terminate() }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }

  func application(_: NSApplication, open urls: [URL]) {
    for url in urls { open(url) }
  }

  func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
    window?.makeKeyAndOrderFront(nil)
    return true
  }

  func webView(_: WKWebView, didFinish _: WKNavigation!) { deliverPendingRoute() }

  func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
  }

  func webView(_: WKWebView, navigationAction _: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }

  func download(_: WKDownload, decideDestinationUsing _: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = suggestedFilename
    panel.allowedContentTypes = [.json]
    completionHandler(panel.runModal() == .OK ? panel.url : nil)
  }

  private func startWebApp(in web: WKWebView) {
    let resources = Bundle.main.resourceURL!.appendingPathComponent("site")
    let bundledNode = resources.appendingPathComponent("node/bin/node")
    let process = Process()
    process.currentDirectoryURL = resources
    if FileManager.default.isExecutableFile(atPath: bundledNode.path) {
      process.executableURL = bundledNode
      process.arguments = ["node_modules/vinext/dist/cli.js", "start", "--port", "3000"]
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = ["node", "node_modules/vinext/dist/cli.js", "start", "--port", "3000"]
    }
    do {
      try process.run()
      server = process
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
        self?.webView?.load(URLRequest(url: URL(string: "http://127.0.0.1:3000")!))
      }
    } catch {
      web.loadHTMLString("<h2>无法启动人物事件库</h2><p>请重新打开应用，或重新安装。</p>", baseURL: nil)
    }
  }

  private func open(_ url: URL) {
    guard url.scheme == "person-event-atlas", url.host == "event", let id = url.pathComponents.dropFirst().first, !id.isEmpty else { return }
    pendingEventID = id.removingPercentEncoding ?? id
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    deliverPendingRoute()
  }

  private func deliverPendingRoute() {
    guard let eventID = pendingEventID,
          let data = try? JSONEncoder().encode(eventID),
          let literal = String(data: data, encoding: .utf8) else { return }
    webView?.evaluateJavaScript("window.__personEventPendingEventID = \(literal); window.dispatchEvent(new CustomEvent('desktop-open-event', { detail: \(literal) }));")
  }
}

@main
struct PersonEventApplication {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }
}
