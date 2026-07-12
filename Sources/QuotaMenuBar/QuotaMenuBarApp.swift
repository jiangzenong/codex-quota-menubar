import AppKit
import Combine
import Charts
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
    @Published var analytics = UsageAnalyticsSnapshot.unavailable
    @Published var isOrb = false
    @Published var english = false
    func refresh() { Task { self.snapshot = await QuotaAPI.fetch(); self.analytics = await QuotaAPI.fetchOfficialAnalytics() } }
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
        menu.addItem(withTitle: panel?.isVisible == true ? "隐藏详情窗口" : "显示详情窗口", action: #selector(togglePanel), keyEquivalent: "")
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
            panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 640, height: 520), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            panel?.title = "Codex 额度"
            panel?.level = .floating
            panel?.hidesOnDeactivate = false
            panel?.isMovableByWindowBackground = true
            panel?.contentView = NSHostingView(rootView: DetailView(model: model, close: { [weak self] in self?.panel?.orderOut(nil) }, openUsage: { [weak self] in self?.openUsage() }))
            panel?.center()
        }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
    private func applyWindowMode(_ isOrb: Bool) {
        guard let panel else { return }
        let size = isOrb ? NSSize(width: 164, height: 164) : NSSize(width: 640, height: 520)
        let origin = NSPoint(x: panel.frame.midX - size.width / 2, y: panel.frame.midY - size.height / 2)
        panel.styleMask = isOrb ? [.borderless, .fullSizeContentView] : [.titled, .closable, .fullSizeContentView]
        panel.isOpaque = !isOrb
        panel.backgroundColor = isOrb ? .clear : .windowBackgroundColor
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
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
    let openUsage: () -> Void
    var body: some View {
        let color = accent
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("CODEX · \(model.snapshot?.plan ?? "PRO")").font(.system(size: 15, weight: .semibold, design: .rounded)); Spacer(); Button(model.english ? "中文" : "EN") { model.english.toggle() }; Button("●") { model.isOrb.toggle() }; Button("×", action: close) }
            if model.isOrb { Text(model.snapshot?.fiveHour.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—").font(.system(size: 42, weight: .bold, design: .rounded)).frame(width: 150, height: 150).background(Circle().fill(.black.opacity(0.88)).overlay(Circle().stroke(AngularGradient(colors: [.cyan, .blue, .purple, .cyan], center: .center), lineWidth: 7)).shadow(color: color.opacity(0.8), radius: 18)).onTapGesture { model.isOrb = false } }
            else {
            HStack(spacing: 0) { topMetric("五小时剩余", value: model.snapshot?.fiveHour.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—", caption: "5h", color: color); Divider(); topMetric("距离下次重置", value: model.snapshot?.fiveHour?.resetsAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—", caption: "", color: .primary); Divider(); topMetric("本周剩余", value: model.snapshot?.weekly.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—", caption: "", color: .primary) }.padding(.vertical, 10)
            if model.analytics.isOfficial { Chart(model.analytics.events, id: \.date) { event in ForEach(event.values.keys.sorted(), id: \.self) { key in BarMark(x: .value("Date", event.date), y: .value("Usage", event.values[key] ?? 0)).foregroundStyle(Color(red: 0.91, green: 0.16, blue: 0.16)) } }.frame(height: 120) }
            else { Button(model.english ? "Official analytics unavailable — Open Usage" : "官方分析数据暂不可用 — 打开 Usage", action: openUsage).font(.caption) }
            }
            if let credits = model.snapshot?.resetCredits { Text("可用重置额度：\(credits)") }
            Divider(); HStack { Text("数据来自官方").font(.caption).foregroundStyle(.secondary); Spacer(); Button("↻") { model.refresh() }.buttonStyle(.plain) }
        }.padding(model.isOrb ? 7 : 24).frame(width: model.isOrb ? 164 : 640).background(model.isOrb ? AnyShapeStyle(.clear) : AnyShapeStyle(.ultraThinMaterial)).tint(color)
    }
    private func topMetric(_ label: String, value: String, caption: String, color: Color) -> some View { VStack(spacing: 7) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.system(size: 31, weight: .medium, design: .rounded)).foregroundStyle(color); if !caption.isEmpty { Text(caption).font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity) }
    private func row(_ label: String, _ value: QuotaWindow?) -> some View {
        VStack(alignment: .leading, spacing: 6) { HStack { Text(label); Spacer(); Text(value.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—") }; ProgressView(value: value?.remainingPercent ?? 0, total: 100); Text(value?.resetsAt.map { "重置：\($0.formatted(date: .abbreviated, time: .shortened))" } ?? "额度信息不可用").font(.caption).foregroundStyle(.secondary) }
    }
    private var accent: Color { let value = model.snapshot?.fiveHour?.remainingPercent ?? 0; return value < 10 ? .orange : value < 50 ? .yellow : .cyan }
}
