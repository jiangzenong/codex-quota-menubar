import AppKit
import Combine
import ServiceManagement
import SwiftUI
import QuotaCore

@main
struct CodexQuotaMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class QuotaModel: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var analytics: UsageAnalytics?
    @Published var isOrb = false
    func refresh() {
        Task { self.snapshot = await QuotaAPI.fetch() }
        Task { if let a = await QuotaAPI.fetchAnalytics() { self.analytics = a } }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = QuotaModel()
    private var statusItem: NSStatusItem!
    private var panel: NSPanel?
    private var subscriptions = Set<AnyCancellable>()

    // Detail and orb share one panel; only the frame differs.
    private let detailSize = NSSize(width: 588, height: 980)
    private let orbSize = NSSize(width: 174, height: 174)
    private let morphDuration = 0.45

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        model.$snapshot.receive(on: RunLoop.main).sink { [weak self] in self?.statusItem.button?.title = QuotaFormatting.menuTitle(for: $0) }.store(in: &subscriptions)
        model.$isOrb.receive(on: RunLoop.main).sink { [weak self] isOrb in self?.applyWindowMode(isOrb) }.store(in: &subscriptions)
        model.refresh(); Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
    }

    @objc private func statusClicked() {
        let route = StatusClickRoute.forRightMouseUp(NSApp.currentEvent?.type == .rightMouseUp)
        if route == .detailWindow { model.refresh(); togglePanel(); return }
        let menu = NSMenu()
        menu.addItem(withTitle: "立即刷新", action: #selector(refresh), keyEquivalent: "")
        menu.addItem(withTitle: panel?.isVisible == true ? "隐藏窗口" : "显示窗口", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: model.isOrb ? "展开详情面板" : "收起为悬浮球", action: #selector(toggleOrb), keyEquivalent: "")
        menu.addItem(withTitle: "打开 Codex 用量", action: #selector(openUsage), keyEquivalent: "")
        let launch = menu.addItem(withTitle: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator()); menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refresh() { model.refresh() }

    @objc private func togglePanel() {
        if panel?.isVisible == true { panel?.orderOut(nil); return }
        if panel == nil {
            let size = model.isOrb ? orbSize : detailSize
            let p = NSPanel(contentRect: .init(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: MorphContainer(model: model))
            p.contentView = host
            p.center()
            panel = p
        }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleOrb() {
        withAnimation(.spring(response: morphDuration, dampingFraction: 0.82)) { model.isOrb.toggle() }
    }

    /// Resizes the shared panel to the target mode, keeping its center fixed so the
    /// detail card visually collapses into the orb (and back), synced with the SwiftUI spring.
    private func applyWindowMode(_ isOrb: Bool) {
        guard let panel else { return }
        let size = isOrb ? orbSize : detailSize
        let current = panel.frame
        let origin = NSPoint(x: current.midX - size.width / 2, y: current.midY - size.height / 2)
        let target = NSRect(origin: origin, size: size)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = morphDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        }
    }

    @objc private func openUsage() { NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex/settings/usage")!) }
    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
