import AppKit
import Combine
import ServiceManagement
import SwiftUI
import QuotaCore

// MARK: - Draggable NSHostingView

private class DraggableHostingView<Content: View>: NSHostingView<Content> {
    var onTap: (() -> Void)?

    private var mouseDownScreen: NSPoint?
    private var windowStartOrigin: NSPoint?
    private var hasDragged = false

    override func mouseDown(with event: NSEvent) {
        mouseDownScreen = NSEvent.mouseLocation
        windowStartOrigin = window?.frame.origin
        hasDragged = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startOrigin = windowStartOrigin, let startScreen = mouseDownScreen else { super.mouseDragged(with: event); return }
        hasDragged = true
        let now = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + (now.x - startScreen.x),
                                       y: startOrigin.y + (now.y - startScreen.y)))
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if !hasDragged {
            let down = mouseDownScreen ?? NSEvent.mouseLocation
            if hypot(NSEvent.mouseLocation.x - down.x, NSEvent.mouseLocation.y - down.y) < 4 { onTap?() }
        }
        mouseDownScreen = nil; windowStartOrigin = nil; hasDragged = false
    }
}

// MARK: - Helpers

@MainActor
private func makeTransparentPanel(size: NSSize) -> NSPanel {
    let p = NSPanel(contentRect: .init(origin: .zero, size: size),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
    p.isFloatingPanel = true
    p.level = .floating
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hidesOnDeactivate = false
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    return p
}

// Menu localization helper (separate from DashboardUI to avoid dependency)
private struct Loc {
    let zh: Bool
    init(_ zh: Bool) { self.zh = zh }
    func t(_ key: String) -> String {
        switch key {
        case "refreshNow": return zh ? "立即刷新" : "Refresh Now"
        case "showWindow": return zh ? "显示窗口" : "Show Window"
        case "hideWindow": return zh ? "隐藏窗口" : "Hide Window"
        case "collapseOrb": return zh ? "收起为悬浮球" : "Collapse to Orb"
        case "expandPanel": return zh ? "展开详情面板" : "Expand Panel"
        case "showOrb": return zh ? "显示悬浮球" : "Show Orb"
        case "openUsage": return zh ? "打开 Codex 用量" : "Open Codex Usage"
        case "launchAtLogin": return zh ? "开机启动" : "Launch at Login"
        case "quit": return zh ? "退出" : "Quit"
        case "switchLang": return zh ? "Switch to English" : "切换中文"
        default: return key
        }
    }
}

// MARK: - App

@main
struct CodexQuotaMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class QuotaModel: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var analytics: UsageAnalytics?
    @Published var isOrb = false
    @Published var isRefreshing = false

    func refresh() {
        isRefreshing = true
        Task { self.snapshot = await QuotaAPI.fetch(); isRefreshing = false }
        Task { if let a = await QuotaAPI.fetchAnalytics() { self.analytics = a } }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = QuotaModel()
    private var statusItem: NSStatusItem!
    private var detailPanel: NSPanel?
    private var orbPanel: NSPanel?
    private var subscriptions = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    private let detailSize = NSSize(width: 512, height: 740)
    private let orbSize    = NSSize(width: 74, height: 74)
    private var detailOrigin: NSPoint?
    private var orbOrigin: NSPoint?

    static var refreshTimerDidChange: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if UserDefaults.standard.object(forKey: "appTheme") == nil {
            let isDark = NSApp.effectiveAppearance.name == .darkAqua || NSApp.effectiveAppearance.name == .vibrantDark
            UserDefaults.standard.set(isDark ? AppTheme.dark.rawValue : AppTheme.light.rawValue, forKey: "appTheme")
        }
        if UserDefaults.standard.object(forKey: "appLocale") == nil {
            UserDefaults.standard.set("zh", forKey: "appLocale")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        model.$snapshot.receive(on: RunLoop.main).sink { [weak self] in
            self?.statusItem.button?.title = QuotaFormatting.menuTitle(for: $0)
        }.store(in: &subscriptions)

        startRefreshTimer()
        AppDelegate.refreshTimerDidChange = { [weak self] in self?.startRefreshTimer() }
        model.refresh()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let secs = TimeInterval(Int(UserDefaults.standard.string(forKey: "refreshInterval") ?? "60") ?? 60)
        guard secs > 0 else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: secs, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
    }

    // MARK: - Menu

    @objc private func statusClicked() {
        let route = StatusClickRoute.forRightMouseUp(NSApp.currentEvent?.type == .rightMouseUp)
        if route == .detailWindow { model.refresh(); togglePanel(); return }
        let isZh = (UserDefaults.standard.string(forKey: "appLocale") ?? "zh") == "zh"
        let l = Loc(isZh)
        let menu = NSMenu()
        menu.addItem(withTitle: l.t("refreshNow"), action: #selector(refresh), keyEquivalent: "")
        menu.addItem(withTitle: detailPanel?.isVisible == true ? l.t("hideWindow") : l.t("showWindow"), action: #selector(togglePanel), keyEquivalent: "")
        let orbLabel: String = {
            if orbPanel?.isVisible == true { return l.t("expandPanel") }
            if detailPanel?.isVisible == true { return l.t("collapseOrb") }
            return l.t("showOrb")
        }()
        menu.addItem(withTitle: orbLabel, action: #selector(toggleOrb), keyEquivalent: "")
        menu.addItem(withTitle: l.t("openUsage"), action: #selector(openUsage), keyEquivalent: "")
        menu.addItem(withTitle: l.t("switchLang"), action: #selector(toggleLanguage), keyEquivalent: "")
        let launch = menu.addItem(withTitle: l.t("launchAtLogin"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator()); menu.addItem(withTitle: l.t("quit"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refresh() { model.refresh() }

    // MARK: - Panel Management

    @objc private func togglePanel() {
        if detailPanel?.isVisible == true { hideAll(); return }
        showDetail()
    }

    private func showDetail() {
        if let orb = orbPanel, orb.isVisible { orbOrigin = orb.frame.origin }
        orbPanel?.orderOut(nil)
        if detailPanel == nil {
            let p = makeTransparentPanel(size: detailSize)
            p.hasShadow = true
            let host = DraggableHostingView(rootView: DetailView(model: model, collapse: { [weak self] in
                self?.collapseToOrb()
            }))
            p.contentView = host
            detailPanel = p
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.detailOrigin = self?.detailPanel?.frame.origin }
            }
        }
        if let origin = detailOrigin { detailPanel?.setFrameOrigin(origin) }
        else { detailPanel?.center() }
        model.isOrb = false
        NSApp.activate(ignoringOtherApps: true)
        detailPanel?.makeKeyAndOrderFront(nil)
    }

    private func collapseToOrb() {
        guard let detail = detailPanel, detail.isVisible else { return }
        detailOrigin = detail.frame.origin
        detail.orderOut(nil)
        let target = orbOrigin ?? NSPoint(x: detail.frame.midX - orbSize.width/2, y: detail.frame.midY - orbSize.height/2)
        showOrb(at: target)
    }

    private func showOrb(at origin: NSPoint) {
        if orbPanel == nil {
            let p = makeTransparentPanel(size: orbSize)
            p.hasShadow = true
            let host = DraggableHostingView(rootView: FloatingBallView(model: model))
            host.wantsLayer = true; host.layer?.backgroundColor = CGColor.clear
            host.onTap = { [weak self] in self?.expandFromOrb() }
            p.contentView = host
            orbPanel = p
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.orbOrigin = self?.orbPanel?.frame.origin }
            }
        }
        model.isOrb = true
        orbPanel?.setFrameOrigin(origin)
        orbPanel?.makeKeyAndOrderFront(nil)
    }

    private func expandFromOrb() {
        guard let orb = orbPanel, orb.isVisible else { return }
        orbOrigin = orb.frame.origin
        orb.orderOut(nil)
        model.isOrb = false
        if let origin = detailOrigin { detailPanel?.setFrameOrigin(origin) }
        else { detailPanel?.setFrameOrigin(NSPoint(x: orb.frame.midX - detailSize.width/2, y: orb.frame.midY - detailSize.height/2)) }
        NSApp.activate(ignoringOtherApps: true)
        detailPanel?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleOrb() {
        if orbPanel?.isVisible == true {
            expandFromOrb()
        } else if detailPanel?.isVisible == true {
            collapseToOrb()
        } else {
            // Neither visible — show orb at saved position or screen center
            let origin = orbOrigin ?? NSPoint(
                x: (NSScreen.main?.frame.midX ?? 400) - orbSize.width/2,
                y: (NSScreen.main?.frame.midY ?? 400) - orbSize.height/2)
            showOrb(at: origin)
        }
    }

    private func hideAll() {
        detailPanel?.orderOut(nil)
        orbPanel?.orderOut(nil)
        model.isOrb = false
    }

    // MARK: - Actions

    @objc private func toggleLanguage() {
        let current = UserDefaults.standard.string(forKey: "appLocale") ?? "zh"
        UserDefaults.standard.set(current == "zh" ? "en" : "zh", forKey: "appLocale")
    }

    @objc private func openUsage() {
        NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex/settings/usage")!)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension CGRect { var center: NSPoint { NSPoint(x: midX, y: midY) } }
