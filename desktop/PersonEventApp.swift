import Cocoa
import WebKit

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

  func webView(_: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame _: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
    let alert = NSAlert()
    alert.messageText = prompt
    let input = NSTextField(string: defaultText ?? "")
    input.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
    alert.accessoryView = input
    alert.addButton(withTitle: "保存")
    alert.addButton(withTitle: "取消")
    completionHandler(alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKDownloadDelegate {
  private let dialogs = DialogDelegate()
  private var server: Process?
  private var window: NSWindow?
  private var webView: WKWebView?

  func applicationDidFinishLaunching(_: Notification) {
    NSApp.setActivationPolicy(.regular)
    let resources = Bundle.main.resourceURL!.appendingPathComponent("site")
    let node = resources.appendingPathComponent("node/bin/node")
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "人物事件库"
    window.center()
    let web = WKWebView(frame: window.contentView!.bounds)
    web.uiDelegate = dialogs
    web.navigationDelegate = self
    web.autoresizingMask = [.width, .height]
    window.contentView?.addSubview(web)
    self.window = window
    webView = web
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    guard FileManager.default.isExecutableFile(atPath: node.path) else {
      web.loadHTMLString("<h2>无法启动人物事件库</h2><p>应用资源不完整，请重新安装。</p>", baseURL: nil)
      return
    }
    let process = Process()
    process.executableURL = node
    process.currentDirectoryURL = resources
    process.arguments = ["node_modules/vinext/dist/cli.js", "start", "--port", "3000"]
    do {
      try process.run()
      server = process
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.webView?.load(URLRequest(url: URL(string: "http://127.0.0.1:3000")!)) }
    } catch {
      web.loadHTMLString("<h2>无法启动人物事件库</h2><p>请重新打开应用，或重新安装。</p>", baseURL: nil)
    }
  }

  func applicationWillTerminate(_: Notification) { if server?.isRunning == true { server?.terminate() } }
  func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }

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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
