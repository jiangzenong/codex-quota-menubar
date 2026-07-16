import AppKit
import Combine
import ServiceManagement
import SwiftUI
import QuotaCore

// MARK: - Draggable NSHostingView

private class DraggableHostingView<Content: View>: NSHostingView<Content> {
    private let dragThreshold: CGFloat
    private let onDragStateChange: (Bool) -> Void
    private let onRightMouseUp: ((NSEvent, NSView) -> Void)?
    private var mouseDownScreen: NSPoint?
    private var windowStartOrigin: NSPoint?
    private var hasDragged = false

    required init(rootView: Content) {
        self.dragThreshold = 0
        self.onDragStateChange = { _ in }
        self.onRightMouseUp = nil
        super.init(rootView: rootView)
    }

    init(
        rootView: Content,
        dragThreshold: CGFloat,
        onDragStateChange: @escaping (Bool) -> Void,
        onRightMouseUp: ((NSEvent, NSView) -> Void)? = nil
    ) {
        self.dragThreshold = dragThreshold
        self.onDragStateChange = onDragStateChange
        self.onRightMouseUp = onRightMouseUp
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownScreen = NSEvent.mouseLocation
        windowStartOrigin = window?.frame.origin
        hasDragged = false
        onDragStateChange(false)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startOrigin = windowStartOrigin, let startScreen = mouseDownScreen else { super.mouseDragged(with: event); return }
        if !hasDragged, dragThreshold > 0 {
            let now = NSEvent.mouseLocation
            let movement = NSPoint(x: now.x - startScreen.x, y: now.y - startScreen.y)
            guard isOrbDragMovement(movement) else { return }
        }
        hasDragged = true
        onDragStateChange(true)
        let now = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + (now.x - startScreen.x),
                                       y: startOrigin.y + (now.y - startScreen.y)))
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onDragStateChange(false)
        mouseDownScreen = nil; windowStartOrigin = nil; hasDragged = false
    }

    override func rightMouseUp(with event: NSEvent) {
        onRightMouseUp?(event, self)
    }
}

let orbDragThreshold: CGFloat = 6

func isOrbDragMovement(_ movement: NSPoint) -> Bool {
    movement.x * movement.x + movement.y * movement.y > orbDragThreshold * orbDragThreshold
}

// MARK: - Helpers

@MainActor
enum SurfacePanelRole {
    case detail
    case orb
}

let statusItemActionEvents: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp]

@MainActor
func makeTransparentPanel(size: NSSize, role: SurfacePanelRole) -> NSPanel {
    let p = NSPanel(contentRect: .init(origin: .zero, size: size),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hidesOnDeactivate = false
    switch role {
    case .detail:
        p.isFloatingPanel = false
        p.level = .normal
        p.collectionBehavior = [.fullScreenAuxiliary]
    case .orb:
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
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
        case "showOrb": return zh ? "显示悬浮球" : "Show Orb"
        case "hideOrb": return zh ? "隐藏悬浮球" : "Hide Orb"
        case "openUsage": return zh ? "打开 Codex 用量" : "Open Codex Usage"
        case "launchAtLogin": return zh ? "开机启动" : "Launch at Login"
        case "quit": return zh ? "退出" : "Quit"
        case "switchLang": return zh ? "Switch to English" : "切换中文"
        default: return key
        }
    }
}

@MainActor
func makeOrbMenu(isZh: Bool, isDetailVisible: Bool) -> NSMenu {
    let l = Loc(isZh)
    let menu = NSMenu()
    menu.addItem(withTitle: l.t("refreshNow"), action: #selector(AppDelegate.refresh), keyEquivalent: "")
    menu.addItem(
        withTitle: isDetailVisible ? l.t("hideWindow") : l.t("showWindow"),
        action: #selector(AppDelegate.togglePanel),
        keyEquivalent: ""
    )
    menu.addItem(withTitle: l.t("hideOrb"), action: #selector(AppDelegate.hideOrb), keyEquivalent: "")
    return menu
}

// MARK: - App

@main
struct CodexQuotaMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

enum QuotaRefreshTrigger {
    case applicationLaunch
    case timer
    case manual
    case detailPresentation

    var requestsRefresh: Bool {
        switch self {
        case .applicationLaunch, .timer, .manual: true
        case .detailPresentation: false
        }
    }
}

@MainActor final class QuotaModel: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var analytics: UsageAnalytics?
    @Published var isOrb = false
    @Published var isOrbDragging = false
    @Published var isRefreshing = false

    private let fetchQuota: @MainActor () async -> QuotaSnapshot
    private let fetchAnalytics: @MainActor () async -> UsageAnalytics?
    private var refreshTask: Task<Void, Never>?

    init(fetchQuota: @escaping @MainActor () async -> QuotaSnapshot = { await QuotaAPI.fetch() },
         fetchAnalytics: @escaping @MainActor () async -> UsageAnalytics? = { await QuotaAPI.fetchAnalytics() }) {
        self.fetchQuota = fetchQuota
        self.fetchAnalytics = fetchAnalytics
    }

    func refresh(trigger: QuotaRefreshTrigger = .manual) {
        guard trigger.requestsRefresh else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            async let nextAnalytics = fetchAnalytics()

            let nextSnapshot = await fetchQuota()
            if nextSnapshot.status == .unavailable,
               let current = snapshot,
               current.status == .ok || current.status == .stale {
                snapshot = .init(plan: current.plan, windows: current.windows,
                                 resetCredits: current.resetCredits,
                                 resetCreditExpirations: current.resetCreditExpirations,
                                 refreshedAt: current.refreshedAt, status: .stale,
                                 message: nextSnapshot.message)
            } else {
                snapshot = nextSnapshot
            }

            let analyticsResult = await nextAnalytics
            if let analyticsResult { analytics = analyticsResult }
            isRefreshing = false
        }
    }

    func waitForRefreshForTesting() async {
        await refreshTask?.value
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = QuotaModel()
    private var statusItem: NSStatusItem!
    var detailPanel: NSPanel?
    private(set) var orbPanel: NSPanel?
    private var subscriptions = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    private let detailSize = NSSize(width: 512, height: 740)
    private let orbSize    = NSSize(width: orbCanvasSize, height: orbCanvasSize)
    private var detailOrigin: NSPoint?
    private var orbOrigin: NSPoint?

    static var refreshTimerDidChange: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installApplicationMenu()

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
        statusItem.button?.sendAction(on: statusItemActionEvents)

        model.$snapshot.receive(on: RunLoop.main).sink { [weak self] in
            self?.updateStatusTitle(for: $0)
        }.store(in: &subscriptions)

        showInitialSurfaces()
        startRefreshTimer()
        AppDelegate.refreshTimerDidChange = { [weak self] in self?.startRefreshTimer() }
        model.refresh(trigger: .applicationLaunch)
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let secs = TimeInterval(Int(UserDefaults.standard.string(forKey: "refreshInterval") ?? "60") ?? 60)
        guard secs > 0 else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: secs, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh(trigger: .timer) }
        }
    }

    // MARK: - Menu

    @objc func installApplicationMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let isZh = (UserDefaults.standard.string(forKey: "appLocale") ?? "zh") == "zh"
        let quitItem = NSMenuItem(title: Loc(isZh).t("quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        let route = StatusClickRoute.forRightMouseUp(event?.type == .rightMouseUp)
        if route == .statusPanel {
            togglePanel()
            return
        }
        let isZh = (UserDefaults.standard.string(forKey: "appLocale") ?? "zh") == "zh"
        let l = Loc(isZh)
        let menu = NSMenu()
        menu.addItem(withTitle: l.t("refreshNow"), action: #selector(refresh), keyEquivalent: "")
        menu.addItem(withTitle: detailPanel?.isVisible == true ? l.t("hideWindow") : l.t("showWindow"), action: #selector(togglePanel), keyEquivalent: "")
        let orbLabel = orbPanel?.isVisible == true ? l.t("hideOrb") : l.t("showOrb")
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

    @objc func refresh() { model.refresh(trigger: .manual) }

    // MARK: - Panel Management

    @objc func togglePanel() {
        if detailPanel?.isVisible == true { hideDetail(); return }
        showDetail()
    }

    func showDetail() {
        ensureDetailPanel()
        if let origin = detailOrigin { detailPanel?.setFrameOrigin(origin) }
        else { detailPanel?.center() }
        detailOrigin = detailPanel?.frame.origin
        NSApp.activate(ignoringOtherApps: true)
        detailPanel?.makeKeyAndOrderFront(nil)
    }

    func hideDetail() {
        if let detail = detailPanel, detail.isVisible { detailOrigin = detail.frame.origin }
        detailPanel?.orderOut(nil)
    }

    func ensureDetailPanel() {
        guard detailPanel == nil else { return }
        let p = makeTransparentPanel(size: detailSize, role: .detail)
        p.hasShadow = true
        let host = DraggableHostingView(rootView: DetailView(
            model: model,
            close: { [weak self] in self?.hideDetail() },
            toggleOrb: { [weak self] in self?.toggleOrb() }
        ))
        p.contentView = host
        detailPanel = p
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.detailOrigin = self?.detailPanel?.frame.origin }
        }
    }

    private func showOrb(at origin: NSPoint) {
        if orbPanel == nil {
            let p = makeTransparentPanel(size: orbSize, role: .orb)
            p.hasShadow = true
            let host = DraggableHostingView(rootView: FloatingBallView(model: model) { [weak self] action in
                switch action {
                case .toggleDetail: self?.togglePanel()
                case .closeOrb: self?.hideOrb()
                }
            }, dragThreshold: orbDragThreshold, onDragStateChange: { [weak self] isDragging in
                self?.model.isOrbDragging = isDragging
            }, onRightMouseUp: { [weak self] event, view in
                self?.showOrbMenu(for: event, in: view)
            })
            host.wantsLayer = true; host.layer?.backgroundColor = CGColor.clear
            p.contentView = host
            orbPanel = p
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.orbOrigin = self?.orbPanel?.frame.origin }
            }
        }
        model.isOrb = true
        model.isOrbDragging = false
        orbPanel?.setFrameOrigin(origin)
        orbPanel?.makeKeyAndOrderFront(nil)
    }

    func showOrb() {
        if orbPanel?.isVisible == true { return }
        let origin = orbOrigin ?? NSPoint(
            x: (NSScreen.main?.frame.midX ?? 400) - orbSize.width / 2,
            y: (NSScreen.main?.frame.midY ?? 400) - orbSize.height / 2
        )
        showOrb(at: origin)
    }

    func showInitialSurfaces() {
        showOrb()
    }

    @objc func hideOrb() {
        if let orb = orbPanel, orb.isVisible { orbOrigin = orb.frame.origin }
        orbPanel?.orderOut(nil)
        model.isOrb = false
        model.isOrbDragging = false
    }

    @objc private func toggleOrb() {
        if orbPanel?.isVisible == true { hideOrb() }
        else { showOrb() }
    }

    private func showOrbMenu(for event: NSEvent, in view: NSView) {
        let isZh = (UserDefaults.standard.string(forKey: "appLocale") ?? "zh") == "zh"
        let menu = makeOrbMenu(isZh: isZh, isDetailVisible: detailPanel?.isVisible == true)
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: event.locationInWindow, in: view)
    }

    // MARK: - Actions

    @objc private func toggleLanguage() {
        let current = UserDefaults.standard.string(forKey: "appLocale") ?? "zh"
        UserDefaults.standard.set(current == "zh" ? "en" : "zh", forKey: "appLocale")
        updateStatusTitle(for: model.snapshot)
    }

    private func updateStatusTitle(for snapshot: QuotaSnapshot?) {
        let isZh = (UserDefaults.standard.string(forKey: "appLocale") ?? "zh") == "zh"
        statusItem.button?.title = QuotaFormatting.menuTitle(
            for: snapshot,
            quotaLabel: isZh ? "额度" : "Quota",
            loadingLabel: isZh ? "数据加载中..." : "Loading data...",
            unavailableLabel: isZh ? "数据暂不可用" : "Data unavailable",
            signedOutLabel: isZh ? "请登录 Codex" : "Sign in to Codex")
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
