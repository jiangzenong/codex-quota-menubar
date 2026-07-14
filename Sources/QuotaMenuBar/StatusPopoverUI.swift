import SwiftUI
import QuotaCore

enum StatusPopoverSection: Equatable {
    case quotaOverview
    case detailsLink
}

let statusPopoverSections: [StatusPopoverSection] = [.quotaOverview, .detailsLink]

enum StatusPopoverHeaderElement: Equatable {
    case syncStatus
    case refresh
}

let statusPopoverHeaderElements: [StatusPopoverHeaderElement] = [.syncStatus, .refresh]
let statusPopoverQuotaColumnCount = 1

@MainActor
func statusPopoverContentSize(for controller: NSHostingController<StatusPopoverView>) -> NSSize {
    let measured = controller.sizeThatFits(in: CGSize(
        width: SurfaceLayout.popoverWidth,
        height: .greatestFiniteMagnitude
    ))
    return NSSize(width: SurfaceLayout.popoverWidth, height: ceil(measured.height))
}

struct StatusPopoverView: View {
    @ObservedObject var model: QuotaModel
    let openDetail: () -> Void

    @AppStorage("appTheme") private var themeSelection: String = AppTheme.dark.rawValue
    @AppStorage("appLocale") private var localeSelection: String = AppLocale.zh.rawValue

    private var theme: AppTheme { AppTheme(rawValue: themeSelection) ?? .dark }
    private var colors: AppColors { .forTheme(theme) }
    private var loc: AppLocale { AppLocale(rawValue: localeSelection) ?? .zh }
    private var snapshot: QuotaSnapshot? { model.snapshot }
    private var quotaWindows: [QuotaWindow] { QuotaFormatting.sortedWindows(snapshot?.windows ?? []) }

    var body: some View {
        VStack(alignment: .leading, spacing: SurfaceLayout.sectionSpacing) {
            header
            quotaOverview
            detailsLink
        }
        .padding(SurfaceLayout.outerPadding)
        .frame(width: SurfaceLayout.popoverWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(colors.bg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
            Spacer(minLength: 4)
            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: SurfaceLayout.controlSize, height: SurfaceLayout.controlSize)
                    .background(RoundedRectangle(cornerRadius: 8).fill(colors.buttonBg))
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
        }
    }

    private var quotaOverview: some View {
        VStack(alignment: .leading, spacing: SurfaceLayout.contentSpacing) {
            Text(loc.t("quotaOverview"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.textPrimary)

            if quotaWindows.isEmpty {
                Text(loc.t("noData"))
                    .font(.system(size: 12))
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible()),
                        count: statusPopoverQuotaColumnCount
                    ),
                    spacing: SurfaceLayout.contentSpacing
                ) {
                    ForEach(Array(quotaWindows.enumerated()), id: \.element.id) { index, window in
                        QuotaCard(
                            percent: window.remainingPercent,
                            percentText: QuotaFormatting.percentText(window.remainingPercent),
                            watermark: QuotaFormatting.periodLabel(for: window) ?? loc.t("quota"),
                            accent: Accent.seriesColors[index % Accent.seriesColors.count],
                            prefix: loc.t("quotaReset"),
                            time: resetText(for: window),
                            remaining: resetRemaining(for: window),
                            colors: colors
                        )
                    }
                }
            }
        }
    }

    private var detailsLink: some View {
        Button(action: openDetail) {
            HStack {
                Label(loc.t("openDetail"), systemImage: "macwindow")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(colors.textPrimary)
            .padding(.horizontal, 11)
            .frame(height: SurfaceLayout.controlSize)
            .background(RoundedRectangle(cornerRadius: 8).fill(colors.buttonBg))
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        if model.isRefreshing { return loc.t("refreshing") }
        guard let snapshot else { return loc.t("noConnection") }
        switch snapshot.status {
        case .ok: return loc.t("synced")
        case .stale: return loc.t("stale")
        case .signedOut: return loc.t("signedOut")
        case .unavailable:
            let message = snapshot.message ?? ""
            return message.contains("Access denied") || message.contains("VPN")
                ? loc.t("restricted")
                : loc.t("noConnection")
        }
    }

    private var statusColor: Color {
        if model.isRefreshing { return Accent.orange }
        switch snapshot?.status {
        case .ok: return colors.syncDot
        case .stale, .signedOut: return Color(hex: "E0A040")
        case .unavailable, nil: return Color(hex: "E05050")
        }
    }

    private func resetText(for window: QuotaWindow) -> String {
        guard let reset = window.resetsAt else { return loc.t("resetUnknown") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: loc == .zh ? "zh_CN" : "en_US")
        formatter.dateFormat = loc == .zh ? "M月d日 HH:mm" : "MMM d, HH:mm"
        return formatter.string(from: reset)
    }

    private func resetRemaining(for window: QuotaWindow) -> String {
        guard let reset = window.resetsAt else { return "" }
        let seconds = max(0, reset.timeIntervalSinceNow)
        if seconds >= 86_400 {
            return "\(Int(seconds) / 86_400)d \(Int(seconds) % 86_400 / 3_600)h"
        }
        return "\(Int(seconds) / 3_600)h \(Int(seconds) % 3_600 / 60)m"
    }
}
