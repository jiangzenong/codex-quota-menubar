import SwiftUI
import QuotaCore

// MARK: - Color Hex Helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Accent Colors

enum Accent {
    static let orange = Color(hex: "FF8400")
    static let blue   = Color(hex: "4A9FD8")
    static let red    = Color(hex: "D93C15")
    static let green  = Color(hex: "7CE38B")
    static let purple = Color(hex: "A78BFA")
    static let seriesColors: [Color] = [.orange, .blue, .green, .purple]
}

// MARK: - Theme

enum AppTheme: String, CaseIterable { case dark, light }

struct AppColors {
    let bg, cardBg, trackBg, buttonBg: Color
    let textPrimary, textSecondary: Color
    let syncDot, syncText, syncBg: Color
    let ballBg, popoverBorder: Color

    static func forTheme(_ theme: AppTheme) -> AppColors {
        theme == .dark ? AppColors(
            bg: Color(hex: "1A1A1A"), cardBg: Color(hex: "222222"),
            trackBg: Color(hex: "181818"), buttonBg: Color(hex: "2E2E2E"),
            textPrimary: Color(hex: "FFFFFF"), textSecondary: Color(hex: "B8B9B6"),
            syncDot: Color(hex: "7CE38B"), syncText: Color(hex: "B6FFCE"),
            syncBg: Color(hex: "222924"), ballBg: Color(hex: "1A1A1A"),
            popoverBorder: Color(hex: "2E2E2E")) : AppColors(
            bg: Color(hex: "FAFAF7"), cardBg: Color(hex: "F0F0ED"),
            trackBg: Color(hex: "E0E0DD"), buttonBg: Color(hex: "EBEBE8"),
            textPrimary: Color(hex: "1A1A1A"), textSecondary: Color(hex: "8A8A87"),
            syncDot: Color(hex: "004D1A"), syncText: Color(hex: "004D1A"),
            syncBg: Color(hex: "DFE6E1"), ballBg: Color(hex: "F0F0ED"),
            popoverBorder: Color(hex: "E0E0DD"))
    }
}

// MARK: - Locale (Chinese default)

enum AppLocale: String, CaseIterable {
    case zh, en
    var next: AppLocale { self == .zh ? .en : .zh }
    var label: String { self == .zh ? "EN" : "中" }
    func t(_ key: String) -> String { Self.dict[self]?[key] ?? key }

    private static let dict: [AppLocale: [String: String]] = [
        .zh: [
            "quotaOverview": "额度概览", "autoRefresh": "自动刷新",
            "dailyUsage": "每日用量", "past7Days": "近 7 天",
            "modelUsage": "模型用量", "today": "今日",
            "desktopApp": "桌面应用", "synced": "已同步",
            "refreshing": "刷新中…", "signedOut": "未登录",
            "noConnection": "无连接", "restricted": "访问受限",
            "quota": "额度", "quotaReset": "额度重置", "resetUnknown": "重置时间未知",
            "manual": "手动",
            "1min": "1 分钟", "2min": "2 分钟",
            "showWindow": "显示窗口", "hideWindow": "隐藏窗口",
            "collapseOrb": "收起为悬浮球", "expandPanel": "展开详情面板", "showOrb": "显示悬浮球",
            "openUsage": "打开 Codex 用量", "launchAtLogin": "开机启动",
            "quit": "退出", "refreshNow": "立即刷新", "noData": "暂无数据",
        ],
        .en: [
            "quotaOverview": "Quota Overview", "autoRefresh": "Auto Refresh",
            "dailyUsage": "Daily Usage", "past7Days": "Past 7 days",
            "modelUsage": "Model Usage", "today": "Today",
            "desktopApp": "Desktop App", "synced": "Synced",
            "refreshing": "Refreshing…", "signedOut": "Signed Out",
            "noConnection": "No Connection", "restricted": "Access Denied",
            "quota": "Quota", "quotaReset": "Resets", "resetUnknown": "Reset time unknown",
            "manual": "Manual",
            "1min": "1 min", "2min": "2 min",
            "showWindow": "Show Window", "hideWindow": "Hide Window",
            "collapseOrb": "Collapse to Orb", "expandPanel": "Expand Panel", "showOrb": "Show Orb",
            "openUsage": "Open Codex Usage", "launchAtLogin": "Launch at Login",
            "quit": "Quit", "refreshNow": "Refresh Now", "noData": "No data",
        ],
    ]
}

// MARK: - Water Wave (fills orb from bottom, surging surface)

struct WaterWave: Shape {
    let level: Double   // 0…100, how much of the orb is filled
    var phase: CGFloat  // animated horizontal offset
    var amplitude: CGFloat = 3
    var animatableData: CGFloat { get { phase } set { phase = newValue } }

    func path(in rect: CGRect) -> Path {
        let w = rect.width; let h = rect.height
        let waterY = h * CGFloat(1 - level / 100)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: waterY))
        for x in stride(from: 0, through: w, by: 2) {
            let y = waterY + amplitude * sin((x + phase) * .pi / 28)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()
        return path
    }
}

// MARK: - Floating Ball

struct FloatingBallView: View {
    @ObservedObject var model: QuotaModel
    @AppStorage("appTheme") private var themeSelection: String = AppTheme.dark.rawValue
    @State private var wavePhase: CGFloat = 0
    private var theme: AppTheme { AppTheme(rawValue: themeSelection) ?? .dark }
    private var colors: AppColors { .forTheme(theme) }
    private var window: QuotaWindow? { QuotaFormatting.preferredWindow(for: model.snapshot) }
    private var percent: Double { window?.remainingPercent ?? 0 }

    var body: some View {
        ZStack {
            // Background
            Circle().fill(colors.ballBg)
            // Water body — fills from bottom proportional to percent
            WaterWave(level: percent, phase: wavePhase + 40, amplitude: 2.5)
                .fill(Accent.orange.opacity(theme == .dark ? 0.10 : 0.12))
                .clipShape(Circle())
            // Brighter surface layer — lower opacity, different phase
            WaterWave(level: percent, phase: wavePhase, amplitude: 2)
                .fill(Accent.orange.opacity(theme == .dark ? 0.22 : 0.26))
                .clipShape(Circle())
            VStack(spacing: 0) {
                Text(window.map { QuotaFormatting.percentText($0.remainingPercent) } ?? "—")
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundStyle(colors.textPrimary).contentTransition(.numericText())
                if let window, let label = QuotaFormatting.periodLabel(for: window) {
                    Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                }
            }
            // Border
            Circle().stroke(Accent.orange, lineWidth: 2)
        }
        .frame(width: 74, height: 74)
        .clipShape(Circle())
        .contentShape(Circle())
        .onReceive(Timer.publish(every: 0.025, on: .main, in: .common).autoconnect()) { _ in
            wavePhase += 0.6
        }
    }
}

// MARK: - Detail View

struct DetailView: View {
    @ObservedObject var model: QuotaModel
    let collapse: () -> Void
    @AppStorage("appTheme") private var themeSelection: String = AppTheme.dark.rawValue
    @AppStorage("appLocale") private var localeSelection: String = AppLocale.zh.rawValue
    @AppStorage("refreshInterval") private var refreshSelection: String = "60"
    @State private var hoveringButton: String? = nil

    private var theme: AppTheme { AppTheme(rawValue: themeSelection) ?? .dark }
    private var colors: AppColors { .forTheme(theme) }
    private var loc: AppLocale { AppLocale(rawValue: localeSelection) ?? .zh }
    private var snap: QuotaSnapshot? { model.snapshot }
    private var quotaWindows: [QuotaWindow] { QuotaFormatting.sortedWindows(snap?.windows ?? []) }
    private var planName: String { (snap?.plan ?? "").isEmpty ? "Pro" : snap!.plan! }

    private enum SyncState { case synced, refreshing, unavailable, restricted, signedOut }
    private var syncState: SyncState {
        if model.isRefreshing { return .refreshing }
        guard let s = snap?.status else { return .unavailable }
        switch s {
        case .ok, .stale: return .synced
        case .signedOut: return .signedOut
        case .unavailable:
            let msg = snap?.message ?? ""
            return msg.contains("Access denied") || msg.contains("VPN") ? .restricted : .unavailable
        }
    }
    private var syncText: String {
        switch syncState {
        case .synced: return loc.t("synced"); case .refreshing: return loc.t("refreshing")
        case .signedOut: return loc.t("signedOut"); case .restricted: return loc.t("restricted")
        case .unavailable: return loc.t("noConnection")
        }
    }
    private var syncDotColor: Color {
        switch syncState {
        case .synced: return colors.syncDot
        case .refreshing: return Accent.orange
        case .unavailable, .restricted: return Color(hex: "E05050")
        case .signedOut: return Color(hex: "E0A040")
        }
    }
    private var syncBgColor: Color {
        switch syncState {
        case .synced: return colors.syncBg
        case .refreshing: return Accent.orange.opacity(0.15)
        case .unavailable, .restricted: return Color(hex: "E05050").opacity(0.12)
        case .signedOut: return Color(hex: "E0A040").opacity(0.12)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header; quotaOverviewSection; autoRefreshSection
            dailyUsageSection; modelUsageSection
        }
        .padding(16)
        .frame(width: 480)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.bg))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(colors.popoverBorder, lineWidth: 1))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) { planBadge; syncBadge }
            Spacer()
            HStack(spacing: 6) {
                iconButton("arrow.clockwise", id: "refresh") { model.refresh() }
                iconButton(theme == .dark ? "sun.max" : "moon.stars", id: "theme") {
                    themeSelection = (theme == .dark ? AppTheme.light : AppTheme.dark).rawValue
                }
                langButton
                iconButton("minus", id: "collapse") { collapse() }
            }
        }
    }

    private var planBadge: some View {
        Text(planName).font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color(hex: "0A0A0A"))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Accent.orange).clipShape(Capsule())
    }

    private var syncBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(syncDotColor).frame(width: 7, height: 7)
            Text(syncText).font(.system(size: 12, weight: .semibold)).foregroundStyle(syncDotColor)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(syncBgColor).clipShape(Capsule())
    }

    private var langButton: some View {
        Button(action: { localeSelection = loc.next.rawValue }) {
            Text(loc.label).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.textPrimary).frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(colors.buttonBg))
        }.buttonStyle(.plain)
    }

    private func iconButton(_ systemName: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.textPrimary).frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(colors.buttonBg).overlay(RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(hoveringButton == id ? 0.08 : 0))))
        }
        .buttonStyle(.plain)
        .onHover { inside in hoveringButton = inside ? id : nil }
    }

    // MARK: Quota Overview

    private var quotaOverviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc.t("quotaOverview")).font(.system(size: 15, weight: .semibold)).foregroundStyle(colors.textPrimary)
            if quotaWindows.isEmpty {
                Text(loc.t("noData")).font(.system(size: 12)).foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: quotaWindows.count == 1 ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Array(quotaWindows.enumerated()), id: \.element.id) { index, window in
                        QuotaCard(percent: window.remainingPercent,
                                  percentText: QuotaFormatting.percentText(window.remainingPercent),
                                  watermark: QuotaFormatting.periodLabel(for: window) ?? loc.t("quota"),
                                  accent: Accent.seriesColors[index % Accent.seriesColors.count],
                                  prefix: loc.t("quotaReset"), time: resetText(for: window),
                                  remaining: resetRemaining(for: window), colors: colors)
                    }
                }
            }
        }
    }

    private func resetText(for window: QuotaWindow) -> String {
        guard let reset = window.resetsAt else { return loc.t("resetUnknown") }
        let f = DateFormatter()
        f.locale = Locale(identifier: loc == .zh ? "zh_CN" : "en_US")
        f.dateFormat = loc == .zh ? "M月d日 HH:mm" : "MMM d, HH:mm"
        return f.string(from: reset)
    }

    private func resetRemaining(for window: QuotaWindow) -> String {
        guard let reset = window.resetsAt else { return "" }
        let secs = max(0, reset.timeIntervalSinceNow)
        if secs >= 86_400 {
            return "\(Int(secs) / 86_400)d \(Int(secs) % 86_400 / 3_600)h"
        }
        return "\(Int(secs)/3600)h \(Int(secs)%3600/60)m"
    }

    // MARK: Auto Refresh

    private var autoRefreshSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(loc.t("autoRefresh")).font(.system(size: 15, weight: .semibold)).foregroundStyle(colors.textPrimary)
                Spacer()
                Text(intervalLabel(refreshSelection)).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(colors.textPrimary)
            }
            HStack(spacing: 6) {
                ForEach(["30", "60", "120", "0"], id: \.self) { val in
                    let sel = refreshSelection == val
                    Button(action: {
                        refreshSelection = val
                        AppDelegate.refreshTimerDidChange?()
                    }) {
                        Text(intervalLabel(val)).font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(sel ? Color(hex: "0A0A0A") : colors.textSecondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(sel ? Accent.orange : colors.buttonBg))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func intervalLabel(_ val: String) -> String {
        switch val { case "30": "30s"; case "60": loc.t("1min"); case "120": loc.t("2min"); case "0": loc.t("manual"); default: loc.t("1min") }
    }

    // MARK: Daily Usage

    private var dailyUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(loc.t("dailyUsage")).font(.system(size: 15, weight: .semibold)).foregroundStyle(colors.textPrimary)
                Spacer()
                Text(loc.t("past7Days")).font(.system(size: 12)).foregroundStyle(colors.textSecondary)
            }
            if barValues.isEmpty {
                Text(loc.t("noData")).font(.system(size: 12)).foregroundStyle(colors.textSecondary)
                    .frame(height: 180).frame(maxWidth: .infinity)
            } else {
                DailyBarChart(values: barValues, labels: barDayLabels, colors: colors).frame(height: 140)
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(Accent.red).frame(width: 10, height: 10)
                    Text(loc.t("desktopApp")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Accent.red)
                }.frame(maxWidth: .infinity)
            }
        }
    }

    private var analytics: UsageAnalytics? { model.analytics }
    private var barValues: [Double] {
        guard let c = analytics?.desktopCredits, !c.isEmpty else { return [] }
        return c.map(\.value)
    }
    private var barDayLabels: [String] {
        guard let c = analytics?.desktopCredits, !c.isEmpty else { return [] }
        let f = DateFormatter(); f.dateFormat = "MM/dd"
        return c.map { f.string(from: $0.date) }
    }

    // MARK: Model Usage

    private var modelUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(loc.t("modelUsage")).font(.system(size: 15, weight: .semibold)).foregroundStyle(colors.textPrimary)
                Spacer()
                Text(loc.t("past7Days")).font(.system(size: 12)).foregroundStyle(colors.textSecondary)
            }
            if trendLayers.isEmpty {
                Text(loc.t("noData")).font(.system(size: 12)).foregroundStyle(colors.textSecondary)
                    .frame(height: 140).frame(maxWidth: .infinity)
            } else {
                ModelAreaChart(layers: trendLayers, labels: trendLabels, colors: colors).frame(height: 140)
            }
            HStack(spacing: 14) {
                ForEach(trendLegendItems.indices, id: \.self) { i in
                    let item = trendLegendItems[i]
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 8, height: 8)
                        Text(item.label).font(.system(size: 11)).foregroundStyle(colors.textSecondary)
                    }
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private var trendLayers: [[Double]] {
        guard let s = analytics?.modelTurns, !s.isEmpty else { return [] }
        return s.sorted { $0.points.reduce(0,+) > $1.points.reduce(0,+) }
            .map(\.points)
    }

    private var trendLabels: [String] {
        guard let d = analytics?.turnDates, !d.isEmpty else { return [] }
        let f = DateFormatter(); f.dateFormat = "MM/dd"
        return stride(from: 0, through: d.count-1, by: max(1,(d.count-1)/4)).map { f.string(from: d[$0]) }
    }

    private var trendLegendItems: [(color: Color, label: String)] {
        guard let s = analytics?.modelTurns, !s.isEmpty else { return [] }
        return s.sorted { $0.points.reduce(0,+) > $1.points.reduce(0,+) }
            .enumerated().map { i, s in (Accent.seriesColors[i % Accent.seriesColors.count], s.model) }
    }
}

// MARK: - Quota Card

struct QuotaCard: View {
    let percent: Double; let percentText: String; let watermark: String; let accent: Color
    let prefix: String; let time: String; let remaining: String; let colors: AppColors
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(percentText)
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent).contentTransition(.numericText())
                Spacer()
                Text(watermark).font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(LinearGradient(
                        gradient: Gradient(stops: [.init(color: accent.opacity(0.31), location: 0),
                                                    .init(color: accent.opacity(0.02), location: 1)]),
                        startPoint: .top, endPoint: .bottom))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(colors.trackBg).frame(height: 6)
                    RoundedRectangle(cornerRadius: 4).fill(accent)
                        .frame(width: max(0, geo.size.width * CGFloat(percent/100)), height: 6)
                }
            }.frame(height: 6)
            HStack {
                Text(prefix).font(.system(size: 11)).foregroundStyle(colors.textSecondary)
                Text(time).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(colors.textSecondary)
                if !remaining.isEmpty {
                    Spacer()
                    Text(remaining).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(accent)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(colors.cardBg))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.25), lineWidth: 1.5))
    }
}

// MARK: - Daily Bar Chart

struct DailyBarChart: View {
    let values: [Double]; let labels: [String]; let colors: AppColors
    @State private var hoveredIndex: Int?
    private let yLabels = ["100%","75%","50%","25%","0%"]
    private var normalized: [Double] {
        guard let max = values.max(), max > 0 else { return values }
        return values.map { $0 / max }
    }
    var body: some View {
        let data = normalized
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(yLabels.indices, id: \.self) { i in
                    Text(yLabels[i]).font(.system(size: 10, design: .monospaced)).foregroundStyle(colors.textSecondary)
                    if i < yLabels.count-1 { Spacer() }
                }
            }.frame(width: 30).padding(.bottom, 22)
            if data.isEmpty { Spacer() } else {
                GeometryReader { geo in
                    let count = data.count, gap: CGFloat = 4
                    let barW = max(1, (geo.size.width - gap*CGFloat(count-1)) / CGFloat(count))
                    let chartH = max(1, geo.size.height - 22)
                    VStack(spacing: 0) {
                        ZStack(alignment: .bottom) {
                            HStack(alignment: .bottom, spacing: gap) {
                                ForEach(data.indices, id: \.self) { i in
                                    Rectangle().fill(Color.clear).frame(width: barW).frame(maxHeight: .infinity)
                                        .contentShape(Rectangle()).onHover { inside in
                                            withAnimation(.easeInOut(duration: 0.12)) { hoveredIndex = inside ? i : nil }
                                        }
                                }
                            }.frame(height: chartH)
                            HStack(alignment: .bottom, spacing: gap) {
                                ForEach(data.indices, id: \.self) { i in
                                    let h = hoveredIndex == i
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Accent.red.opacity(h ? 1 : (hoveredIndex == nil ? 0.78 : 0.28)))
                                        .frame(width: barW, height: chartH * CGFloat(data[i]))
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if let i = hoveredIndex, i < count {
                                let x = barW/2 + CGFloat(i)*(barW + gap) - 40
                                let y = chartH * CGFloat(1 - data[i]) - 34
                                VStack(spacing: 2) {
                                    Text(labels[i]).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Accent.red)
                                    Text(String(format: "%.0f credits", values[i])).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Accent.red)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 4).fill(colors.cardBg))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Accent.red.opacity(0.3), lineWidth: 0.5))
                                .offset(x: x, y: max(0, y))
                                .fixedSize()
                            }
                        }
                        HStack(spacing: gap) {
                            ForEach(Array(labels.prefix(count).enumerated()), id: \.offset) { _, label in
                                Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(colors.textSecondary).frame(width: barW).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Model Area Chart

struct ModelAreaChart: View {
    let layers: [[Double]]; let labels: [String]; let colors: AppColors
    @State private var hoverX: CGFloat?
    private let yLabels = ["100%","75%","50%","25%","0%"]
    private var normalized: [[Double]] {
        let all = layers.flatMap { $0 }
        guard let max = all.max(), max > 0 else { return layers }
        return layers.map { $0.map { $0 / max } }
    }
    var body: some View {
        let data = normalized
        let isHovered = hoverX != nil
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(yLabels.indices, id: \.self) { i in
                    Text(yLabels[i]).font(.system(size: 10, design: .monospaced)).foregroundStyle(colors.textSecondary)
                    if i < yLabels.count-1 { Spacer() }
                }
            }.frame(width: 30).padding(.bottom, 22)
            if data.isEmpty { Spacer() } else {
                GeometryReader { geo in
                    let chartW = geo.size.width
                    let chartH = max(1, geo.size.height - 22)
                    VStack(spacing: 0) {
                        ZStack {
                            ForEach(data.indices, id: \.self) { i in
                                let accent = Accent.seriesColors[i % Accent.seriesColors.count]
                                let op = isHovered ? min(0.45 - 0.06*Double(i), 0.55) : 0.35 - 0.06*Double(i)
                                AreaShape(points: data[i]).fill(accent.opacity(max(0.1, op)))
                                AreaShape(points: data[i], strokeOnly: true)
                                    .stroke(accent.opacity(isHovered ? 1.0 : 0.85), lineWidth: isHovered ? 1.5 : 1)
                            }
                            // Vertical indicator
                            if let hx = hoverX, chartW > 0 {
                                Rectangle().fill(colors.textSecondary.opacity(0.3)).frame(width: 1)
                                    .position(x: hx, y: chartH/2)
                                // Dots at intersection
                                let idx = min(Int((hx / chartW) * CGFloat((data.first?.count ?? 2)-1)), (data.first?.count ?? 2)-2)
                                let stepX = chartW / CGFloat((data.first?.count ?? 2)-1)
                                ForEach(data.indices, id: \.self) { i in
                                    let accent = Accent.seriesColors[i % Accent.seriesColors.count]
                                    let x = stepX * CGFloat(idx)
                                    let y = chartH * CGFloat(1 - data[i][idx])
                                    Circle().fill(accent).frame(width: 4, height: 4).position(x: x, y: y)
                                }
                            }
                        }
                        .frame(height: chartH)
                        .contentShape(Rectangle())
                        .onHover { _ in }
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc): hoverX = loc.x
                            case .ended: hoverX = nil
                            }
                        }
                        HStack {
                            ForEach(labels.indices, id: \.self) { i in
                                Text(labels[i]).font(.system(size: 10, design: .monospaced)).foregroundStyle(colors.textSecondary)
                                if i < labels.count-1 { Spacer() }
                            }
                        }.padding(.top, 4).frame(height: labels.isEmpty ? 0 : 16)
                    }
                }
            }
        }
    }
}

// MARK: - Area Shape

struct AreaShape: Shape {
    let points: [Double]; var strokeOnly = false
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let stepX = rect.width / CGFloat(points.count-1)
        func pt(_ i: Int) -> CGPoint { CGPoint(x: rect.minX + stepX * CGFloat(i), y: rect.maxY - rect.height * CGFloat(points[i])) }
        path.move(to: pt(0))
        for i in 1..<points.count {
            let prev = pt(i-1), cur = pt(i), midX = (prev.x+cur.x)/2
            path.addCurve(to: cur, control1: CGPoint(x: midX, y: prev.y), control2: CGPoint(x: midX, y: cur.y))
        }
        if !strokeOnly { path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); path.closeSubpath() }
        return path
    }
}

// MARK: - Morphing Container (no longer used — see AppDelegate for dual-panel management)
// DetailView and FloatingBallView are now hosted in separate NSPanels.
