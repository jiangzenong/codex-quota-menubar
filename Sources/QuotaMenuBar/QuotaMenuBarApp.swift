import AppKit
import Combine
import ServiceManagement
import SwiftUI
import QuotaCore

// MARK: - Draggable NSHostingView with tap detection

private class DraggableHostingView<Content: View>: NSHostingView<Content> {
    var onTap: (() -> Void)?
    var acceptsPoint: ((NSPoint, NSRect) -> Bool)?

    private var mouseDownScreen: NSPoint?
    private var windowStartOrigin: NSPoint?
    private var hasDragged = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard acceptsPoint?(point, bounds) ?? true else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownScreen = NSEvent.mouseLocation
        windowStartOrigin = window?.frame.origin
        hasDragged = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startOrigin = windowStartOrigin,
              let startScreen = mouseDownScreen else {
            super.mouseDragged(with: event)
            return
        }
        hasDragged = true
        let now = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(
            x: startOrigin.x + (now.x - startScreen.x),
            y: startOrigin.y + (now.y - startScreen.y)))
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if !hasDragged {
            let down = mouseDownScreen ?? NSEvent.mouseLocation
            let now = NSEvent.mouseLocation
            if hypot(now.x - down.x, now.y - down.y) < 4 {
                onTap?()
            }
        }
        mouseDownScreen = nil
        windowStartOrigin = nil
        hasDragged = false
    }
}

/// Recursively clear opaque layer backgrounds that SwiftUI's internal
/// views paint on top of a transparent window (necessary on macOS 15).
@MainActor
private func clearOpaqueHostingLayers(_ view: NSView) {
    for subview in view.subviews {
        let name = String(describing: type(of: subview))
        if name.contains("Hosting") || name.contains("LayoutHost") || name.contains("PlatformGroup") {
            subview.wantsLayer = true
            subview.layer?.backgroundColor = CGColor.clear
        }
        clearOpaqueHostingLayers(subview)
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

    private let detailSize = NSSize(width: 588, height: 740)
    private let orbSize    = NSSize(width: 150, height: 150)
    private let morphDuration = 0.45

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        model.$snapshot.receive(on: RunLoop.main).sink { [weak self] in
            self?.statusItem.button?.title = QuotaFormatting.menuTitle(for: $0)
        }.store(in: &subscriptions)
        model.$isOrb.receive(on: RunLoop.main).sink { [weak self] isOrb in
            self?.applyWindowMode(isOrb)
        }.store(in: &subscriptions)
        model.refresh()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
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
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = !model.isOrb
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.animationBehavior = .utilityWindow

            let host = DraggableHostingView(rootView: MorphContainer(model: model))
            host.acceptsPoint = { [weak self] point, bounds in
                guard self?.model.isOrb == true else { return true }
                let radius = min(bounds.width, bounds.height) / 2
                let x = point.x - bounds.midX
                let y = point.y - bounds.midY
                return x * x + y * y <= radius * radius
            }
            host.onTap = { [weak self] in
                guard let self, self.model.isOrb else { return }
                self.toggleOrb()
            }
            p.contentView = host
            p.center()
            panel = p
            DispatchQueue.main.async { clearOpaqueHostingLayers(host) }
        }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleOrb() {
        withAnimation(.spring(response: morphDuration, dampingFraction: 0.82)) {
            model.isOrb.toggle()
        }
    }

    private func applyWindowMode(_ isOrb: Bool) {
        guard let panel else { return }
        panel.hasShadow = !isOrb
        let size = isOrb ? orbSize : detailSize
        let current = panel.frame
        let origin = NSPoint(x: current.midX - size.width / 2,
                             y: current.midY - size.height / 2)
        let target = NSRect(origin: origin, size: size)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = morphDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        }
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
