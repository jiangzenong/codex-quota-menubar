import SwiftUI
import QuotaCore

// MARK: - Palette

enum Palette {
    static let cardTop = Color(red: 0.07, green: 0.09, blue: 0.13)
    static let cardBottom = Color(red: 0.03, green: 0.04, blue: 0.07)
    static let panel = Color.white.opacity(0.03)
    static let stroke = Color.white.opacity(0.06)
    static let accent = Color(red: 0.38, green: 0.64, blue: 1.0)
    static let ringStart = Color(red: 0.20, green: 0.80, blue: 0.95)
    static let ringMid = Color(red: 0.35, green: 0.55, blue: 1.0)
    static let ringEnd = Color(red: 0.66, green: 0.42, blue: 0.98)
    static let series = Color(red: 0.95, green: 0.22, blue: 0.28)
    static let borderGlow = LinearGradient(
        colors: [Color(red: 0.20, green: 0.80, blue: 0.95), Color(red: 0.66, green: 0.42, blue: 0.98)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let ringGradient = AngularGradient(
        colors: [ringStart, ringMid, ringEnd, ringStart],
        center: .center, angle: .degrees(-90))
}

// MARK: - Ring gauge

struct RingGauge: View {
    let percent: Double          // 0...100
    var label: String            // e.g. "5h"
    var showShield: Bool = false
    var lineWidth: CGFloat = 10
    var percentFont: Font = .system(size: 40, weight: .semibold, design: .rounded)

    private var fraction: CGFloat { CGFloat(min(100, max(0, percent)) / 100) }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let inset = lineWidth / 2 + 2
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Palette.ringGradient, style: .init(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Palette.ringMid.opacity(0.55), radius: 8)
                // Leading dot marker at the progress head.
                Circle()
                    .fill(.white)
                    .frame(width: lineWidth + 1, height: lineWidth + 1)
                    .offset(y: -(side / 2 - inset))
                    .rotationEffect(.degrees(Double(fraction) * 360 - 90))
                    .shadow(color: Palette.ringEnd.opacity(0.8), radius: 4)

                VStack(spacing: 1) {
                    if showShield {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.accent)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(percent.rounded()))")
                            .font(percentFont)
                            .foregroundStyle(Palette.accent)
                        Text("%")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.accent.opacity(0.9))
                    }
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(inset)
        }
    }
}

// MARK: - Detail window

struct DetailView: View {
    @ObservedObject var model: QuotaModel
    let collapse: () -> Void
    var ns: Namespace.ID

    private var snap: QuotaSnapshot? { model.snapshot }
    private var fivePercent: Double { snap?.fiveHour?.remainingPercent ?? 0 }
    private var weeklyPercent: Double { snap?.weekly?.remainingPercent ?? 0 }
    private var planName: String { (snap?.plan ?? "").isEmpty ? "PRO" : snap!.plan! }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statPanel
            ChartCard(title: "个人使用情况", subtitle: rangeLabel(analytics?.desktopCredits.map(\.date))) {
                BarChart(values: barValues, labels: barLabels)
            }
            ChartCard(title: "各模型轮次趋势", subtitle: rangeLabel(analytics?.turnDates)) {
                AreaChart(layers: trendLayers, labels: trendLabels)
            }
            ChartCard(title: "技能使用", subtitle: "(近 30 天调用次数)", height: 200, showLegend: false) {
                SkillBars(skills: skills)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Palette.cardTop, Palette.cardBottom],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Palette.borderGlow, lineWidth: 1.5)
                .shadow(color: Palette.ringMid.opacity(0.5), radius: 12)
        )
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Palette.ringStart, Palette.ringEnd],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 34, height: 34)
                .overlay(Image(systemName: "cube.fill").font(.system(size: 15)).foregroundStyle(.white))
            HStack(spacing: 6) {
                Text("CODEX").font(.system(size: 18, weight: .bold))
                Text("·").foregroundStyle(.white.opacity(0.4))
                Text(planName).font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.accent)
            }
            Spacer()
            circleButton("arrow.clockwise") { model.refresh() }
            circleButton("circle.circle") { collapse() }
        }
    }

    private func circleButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.05)))
                .overlay(Circle().stroke(Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var statPanel: some View {
        HStack(spacing: 0) {
            statColumn(title: "五小时剩余") {
                RingGauge(percent: fivePercent, label: "5h", showShield: true)
                    .matchedGeometryEffect(id: "ring", in: ns)
                    .frame(width: 128, height: 128)
            }
            divider
            statColumn(title: "距离下次重置") {
                Text(resetCountdown)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxHeight: .infinity)
            }
            divider
            statColumn(title: "本周剩余") {
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(weeklyPercent.rounded()))")
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                        Text("%").font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .foregroundStyle(.white)
                    Text("\(planName) 计划")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 190)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        )
    }

    private func statColumn<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 18)
    }

    private var divider: some View {
        Rectangle().fill(Palette.stroke).frame(width: 1).padding(.vertical, 24)
    }

    // MARK: Derived text

    private var resetCountdown: AttributedString {
        guard let reset = snap?.fiveHour?.resetsAt else { return unit("—", "") }
        let secs = max(0, reset.timeIntervalSinceNow)
        let h = Int(secs) / 3600, m = (Int(secs) % 3600) / 60
        var out = unit("\(h)", "h")
        out.append(AttributedString(" "))
        out.append(unit("\(m)", "m"))
        return out
    }

    private func unit(_ value: String, _ suffix: String) -> AttributedString {
        var v = AttributedString(value)
        v.font = .system(size: 44, weight: .semibold, design: .rounded)
        var s = AttributedString(suffix)
        s.font = .system(size: 22, weight: .medium, design: .rounded)
        s.foregroundColor = .white.opacity(0.6)
        v.append(s)
        return v
    }

    private func rangeLabel(_ dates: [Date]?) -> String {
        let cal = Calendar.current
        let end = dates?.last ?? snap?.weekly?.resetsAt ?? .now
        let start = dates?.first ?? cal.date(byAdding: .day, value: -29, to: end) ?? end
        let f = DateFormatter(); f.dateFormat = "M月d日"
        return "(\(f.string(from: start)) - \(f.string(from: end)))"
    }

    // MARK: Chart data (real analytics, sample fallback before first load)

    private var analytics: UsageAnalytics? { model.analytics }

    private var barValues: [Double] {
        guard let credits = analytics?.desktopCredits, !credits.isEmpty else { return Self.usageBars }
        return normalize(credits.map(\.value))
    }
    private var barLabels: [String] { axisLabels(analytics?.desktopCredits.map(\.date)) }

    private var trendLayers: [[Double]] {
        guard let series = analytics?.modelTurns, !series.isEmpty else { return Self.trendLayers }
        // Largest-area series first so smaller ones layer on top.
        let ordered = series.sorted { $0.points.reduce(0, +) > $1.points.reduce(0, +) }
        let maxTurn = ordered.flatMap(\.points).max() ?? 1
        return ordered.map { s in s.points.map { maxTurn > 0 ? $0 / maxTurn : 0 } }
    }
    private var trendLabels: [String] { axisLabels(analytics?.turnDates) }

    private var skills: [SkillUsage] { analytics?.skills ?? [] }

    private func normalize(_ values: [Double]) -> [Double] {
        let peak = values.max() ?? 0
        return peak > 0 ? values.map { $0 / peak } : values.map { _ in 0 }
    }

    private func axisLabels(_ dates: [Date]?) -> [String] {
        guard let dates, !dates.isEmpty else { return [] }
        let f = DateFormatter(); f.dateFormat = "M月d日"
        let picks = [0, dates.count / 2, dates.count - 1]
        return picks.map { f.string(from: dates[$0]) }
    }

    // Sample series for the visual design; live API exposes only current windows.
    static let usageBars: [Double] = [
        0.34, 0.95, 0.62, 0.20, 0.24, 0.18, 0.30, 0.44, 0.68, 0.50, 0.55, 0.30, 0.28,
        0.95, 0.62, 0.34, 0.22, 0.66, 0.44, 0.20, 0.42, 0.60, 0.88, 0.55, 0.62, 0.30, 0.36,
    ]
    static let trendLayers: [[Double]] = [
        [0.10, 0.30, 0.70, 0.55, 0.20, 0.28, 0.62, 0.40, 0.24, 0.30, 0.52, 0.34, 0.18],
        [0.06, 0.20, 0.48, 0.36, 0.14, 0.18, 0.42, 0.26, 0.16, 0.20, 0.34, 0.22, 0.12],
        [0.03, 0.10, 0.26, 0.20, 0.08, 0.10, 0.22, 0.14, 0.09, 0.11, 0.18, 0.12, 0.07],
    ]
}

// MARK: - Chart card chrome

struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    var height: CGFloat = 110
    var showLegend: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                Spacer()
                if showLegend {
                    HStack(spacing: 5) {
                        Circle().fill(Palette.series).frame(width: 7, height: 7)
                        Text("Desktop App").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            content().frame(height: height)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        )
    }
}

// MARK: - Bar chart

struct BarChart: View {
    let values: [Double]
    var labels: [String] = []

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 0) {
                YAxis()
                GeometryReader { geo in
                    let gap: CGFloat = 4
                    let barW = (geo.size.width - gap * CGFloat(max(1, values.count - 1))) / CGFloat(max(1, values.count))
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(values.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(LinearGradient(colors: [Palette.series, Palette.series.opacity(0.65)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: barW, height: max(2, geo.size.height * values[i]))
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            XAxis(labels: labels)
        }
    }
}

// MARK: - Stacked area chart

struct AreaChart: View {
    let layers: [[Double]]   // outer→inner, largest first
    var labels: [String] = []

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 0) {
                YAxis()
                GeometryReader { geo in
                    ZStack {
                        ForEach(layers.indices, id: \.self) { i in
                            let opacity = 0.30 + 0.30 * Double(i)
                            AreaShape(points: layers[i])
                                .fill(Palette.series.opacity(opacity))
                            AreaShape(points: layers[i], strokeOnly: true)
                                .stroke(Palette.series.opacity(0.9), lineWidth: 1)
                        }
                    }
                }
            }
            XAxis(labels: labels)
        }
    }
}

struct AreaShape: Shape {
    let points: [Double]
    var strokeOnly: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let stepX = rect.width / CGFloat(points.count - 1)
        func pt(_ i: Int) -> CGPoint {
            CGPoint(x: rect.minX + stepX * CGFloat(i), y: rect.maxY - rect.height * CGFloat(points[i]))
        }
        // Smooth curve through the points.
        path.move(to: pt(0))
        for i in 1..<points.count {
            let prev = pt(i - 1), cur = pt(i)
            let midX = (prev.x + cur.x) / 2
            path.addCurve(to: cur,
                          control1: CGPoint(x: midX, y: prev.y),
                          control2: CGPoint(x: midX, y: cur.y))
        }
        if !strokeOnly {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Shared Y axis labels

struct YAxis: View {
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(["100%", "50%", "0%"], id: \.self) { label in
                Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                if label != "0%" { Spacer() }
            }
        }
        .frame(width: 34, alignment: .leading)
    }
}

struct XAxis: View {
    let labels: [String]
    var body: some View {
        HStack {
            ForEach(labels.indices, id: \.self) { i in
                Text(labels[i]).font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                if i != labels.count - 1 { Spacer() }
            }
        }
        .padding(.leading, 34)
        .frame(height: labels.isEmpty ? 0 : 12)
    }
}

// MARK: - Skill usage leaderboard

struct SkillBars: View {
    let skills: [SkillUsage]

    var body: some View {
        if skills.isEmpty {
            Text("暂无技能调用数据")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let peak = Double(skills.map(\.count).max() ?? 1)
            VStack(spacing: 8) {
                ForEach(skills.indices, id: \.self) { i in
                    let s = skills[i]
                    HStack(spacing: 10) {
                        Text(s.name)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                            .frame(width: 150, alignment: .leading)
                        GeometryReader { geo in
                            Capsule()
                                .fill(LinearGradient(colors: [Palette.series, Palette.series.opacity(0.6)],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, geo.size.width * CGFloat(Double(s.count) / peak)), height: 10)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        Text("\(s.count)")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Floating ball

struct FloatingBallView: View {
    @ObservedObject var model: QuotaModel
    var ns: Namespace.ID
    private var percent: Double { model.snapshot?.fiveHour?.remainingPercent ?? 0 }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Palette.cardTop, Palette.cardBottom],
                                     center: .center, startRadius: 4, endRadius: 90))
                .overlay(Circle().stroke(Palette.borderGlow, lineWidth: 2))
                .shadow(color: Palette.ringMid.opacity(0.6), radius: 16)
            RingGauge(percent: percent, label: "5h", lineWidth: 8,
                      percentFont: .system(size: 34, weight: .semibold, design: .rounded))
                .matchedGeometryEffect(id: "ring", in: ns)
                .padding(20)
        }
        .frame(width: 150, height: 150)
        .padding(12)
    }
}

// MARK: - Morphing container (mutually-exclusive detail ⇆ orb)

struct MorphContainer: View {
    @ObservedObject var model: QuotaModel
    @Namespace private var ns

    var body: some View {
        ZStack {
            if model.isOrb {
                FloatingBallView(model: model, ns: ns)
                    .transition(.opacity)
                    .onTapGesture { toggle(false) }
            } else {
                DetailView(model: model, collapse: { toggle(true) }, ns: ns)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: model.isOrb)
    }

    private func toggle(_ orb: Bool) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { model.isOrb = orb }
    }
}
