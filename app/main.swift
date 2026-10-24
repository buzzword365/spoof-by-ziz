// Spoof by Ziz: a small Mac app around spoof.py.
// Opening it starts the iPhone tunnel (asks for your password once) and the
// spoofer, and shows the map in its own window. Quitting stops both, so the
// phone goes back to real GPS.

import Cocoa
import WebKit

let port = 8765
let tunneldURL = "http://127.0.0.1:49151/"
let statusURL = "http://127.0.0.1:\(port)/api/status"

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var server: Process?

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    lazy var python = "\(home)/.local/pipx/venvs/pymobiledevice3/bin/python"
    lazy var pmd3 = "\(home)/.local/bin/pymobiledevice3"
    lazy var logPath = "\(home)/Library/Logs/Spoof by Ziz.log"

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        showMessage("Starting…", detail: "Getting the iPhone tunnel and the spoofer ready.")
        guard FileManager.default.isExecutableFile(atPath: python) else {
            showMessage("pymobiledevice3 isn't installed",
                        detail: "Open Terminal, run <code>pipx install pymobiledevice3</code>, then open this app again.")
            return
        }
        DispatchQueue.global().async {
            let tunnelOK = self.startTunnel()
            self.startServer()
            let up = self.waitFor(statusURL, seconds: 20)
            DispatchQueue.main.async {
                if up {
                    self.web.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!))
                    if !tunnelOK {
                        self.notice("The tunnel didn't start, so iPhones on iOS 17 or newer won't move. Quit and reopen the app to try again.")
                    }
                } else {
                    self.showMessage("The spoofer didn't start", detail: "Details are in ~/Library/Logs/Spoof by Ziz.log")
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        // The tunnel watcher (started as root) notices we're gone and stops tunneld itself.
        if let server, server.isRunning {
            server.terminate()
            server.waitUntilExit()
        }
    }

    // MARK: - Background processes

    /// Starts `pymobiledevice3 remote tunneld` as root unless one is already running.
    /// A root watcher loop stops it again once this app quits.
    func startTunnel() -> Bool {
        if responds(tunneldURL) { return true }
        let pid = ProcessInfo.processInfo.processIdentifier
        let shell = """
            /bin/sh -c '"\(pmd3)" remote tunneld >>"\(logPath)" 2>&1 & T=$!; \
            while kill -0 \(pid) 2>/dev/null; do sleep 2; done; kill $T' >/dev/null 2>&1 &
            """
        let script = """
            do shell script "\(appleScriptEscape(shell))" with administrator privileges \
            with prompt "Spoof by Ziz needs your password to open the tunnel to your iPhone."
            """
        var error: NSDictionary?
        DispatchQueue.main.sync { _ = NSAppleScript(source: script)?.executeAndReturnError(&error) }
        if let error {
            log("tunnel not started: \(error)")
            return false
        }
        return waitFor(tunneldURL, seconds: 15)
    }

    func startServer() {
        if responds(statusURL) { return }  // already running from somewhere else
        guard let script = Bundle.main.path(forResource: "spoof", ofType: "py") else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = ["-u", script, "--port", String(port)]
        if let out = logHandle() {
            p.standardOutput = out
            p.standardError = out
        }
        do { try p.run(); server = p } catch { log("server failed to start: \(error)") }
    }

    func responds(_ url: String) -> Bool {
        var request = URLRequest(url: URL(string: url)!)
        request.timeoutInterval = 1
        let done = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            ok = response != nil
            done.signal()
        }.resume()
        done.wait()
        return ok
    }

    func waitFor(_ url: String, seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if responds(url) { return true }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return false
    }

    func logHandle() -> FileHandle? {
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        let handle = FileHandle(forWritingAtPath: logPath)
        handle?.seekToEndOfFile()
        return handle
    }

    func log(_ line: String) {
        logHandle()?.write("\(Date()) app: \(line)\n".data(using: .utf8)!)
    }

    // MARK: - Window

    func buildWindow() {
        let config = WKWebViewConfiguration()
        web = WKWebView(frame: .zero, configuration: config)
        web.uiDelegate = self
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Spoof by Ziz"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)
        window.minSize = NSSize(width: 520, height: 560)
        window.contentView = web
        window.setFrameAutosaveName("SpoofByZizMain")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showMessage(_ title: String, detail: String) {
        web.loadHTMLString("""
            <html><body style="margin:0;height:100vh;display:grid;place-items:center;background:#07080c;color:#f4f5f8;
              font:15px -apple-system,system-ui,sans-serif;text-align:center">
            <div><div style="font:700 88px/0.9 -apple-system,system-ui;letter-spacing:-.04em;
              background:linear-gradient(100deg,#fff,#c9bcff 35%,#7c5cff 60%,#00d4ff);-webkit-background-clip:text;color:transparent">BY ZIZ</div>
            <p style="font-size:18px;font-weight:600;margin:28px 0 6px">\(title)</p>
            <p style="color:#8b90a0;margin:0">\(detail)</p></div></body></html>
            """, baseURL: nil)
    }

    func notice(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Heads up"
        alert.informativeText = text
        alert.beginSheetModal(for: window)
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Spoof by Ziz", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Spoof by Ziz", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Spoof by Ziz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // Without an Edit menu, copy/paste don't work in the search and coordinate fields.
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View")
        view.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "r")
        viewItem.submenu = view

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    @objc func reload() { web.reload() }

    // MARK: - Web view behaviour

    // "Save pin" uses window.prompt(), which WKWebView only shows if we draw it.
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    // Links to other sites (map credits etc.) open in the normal browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated, let url = action.request.url, url.host != "127.0.0.1" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }
}

func appleScriptEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
