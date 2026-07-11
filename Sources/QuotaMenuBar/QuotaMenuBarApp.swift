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
    func refresh() { Task { self.snapshot = await QuotaAPI.fetch() } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = QuotaModel()
    private var statusItem: NSStatusItem!
    private var panel: NSPanel?
    private var subscriptions = Set<AnyCancellable>()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        model.$snapshot.receive(on: RunLoop.main).sink { [weak self] in self?.statusItem.button?.title = QuotaFormatting.menuTitle(for: $0) }.store(in: &subscriptions)
        model.refresh(); Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
    }
    @objc private func statusClicked() {
        let route = StatusClickRoute.forRightMouseUp(NSApp.currentEvent?.type == .rightMouseUp)
        if route == .detailWindow { model.refresh(); togglePanel(); return }
        let menu = NSMenu()
        menu.addItem(withTitle: "立即刷新", action: #selector(refresh), keyEquivalent: "")
        menu.addItem(withTitle: panel?.isVisible == true ? "隐藏详情窗口" : "显示详情窗口", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: "打开 Codex 用量", action: #selector(openUsage), keyEquivalent: "")
        let launch = menu.addItem(withTitle: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator()); menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        }
    }
    @objc private func refresh() { model.refresh() }
    @objc private func togglePanel() {
        if panel?.isVisible == true { panel?.orderOut(nil); return }
        if panel == nil {
            panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 330, height: 300), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            panel?.title = "Codex 额度"; panel?.level = .floating; panel?.isMovableByWindowBackground = true
            panel?.contentView = NSHostingView(rootView: DetailView(model: model, close: { [weak self] in self?.panel?.orderOut(nil) }))
        }
        model.refresh(); panel?.makeKeyAndOrderFront(nil)
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

struct DetailView: View {
    @ObservedObject var model: QuotaModel
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(model.snapshot?.plan ?? "CODEX").font(.headline); Spacer(); Button("刷新") { model.refresh() }; Button("关闭", action: close) }
            row("5 小时额度", model.snapshot?.fiveHour); row("本周额度", model.snapshot?.weekly)
            if let credits = model.snapshot?.resetCredits { Text("可用重置额度：\(credits)") }
            Divider(); Text(model.snapshot?.message ?? "上次刷新：\(model.snapshot?.refreshedAt.formatted(date: .omitted, time: .shortened) ?? "—")").font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 330)
    }
    private func row(_ label: String, _ value: QuotaWindow?) -> some View {
        VStack(alignment: .leading, spacing: 6) { HStack { Text(label); Spacer(); Text(value.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—") }; ProgressView(value: value?.remainingPercent ?? 0, total: 100); Text(value?.resetsAt.map { "重置：\($0.formatted(date: .abbreviated, time: .shortened))" } ?? "额度信息不可用").font(.caption).foregroundStyle(.secondary) }
    }
}
