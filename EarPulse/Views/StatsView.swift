import Charts
import Combine
import SwiftUI

@MainActor
private final class StatsViewState: ObservableObject {
    @Published var selectedDeviceName: String? = nil
    @Published var selectedRange: StatsTimeRange = .week
    @Published var periodOffset: Int = 0
    @Published var selectedBarLabel: String? = nil
}

/// 旗舰级液态玻璃「使用时间统计」（全交互震动适配 + 等宽数字翻滚 + 交互式柱状图）
struct StatsView: View {
    @EnvironmentObject private var dataStore: HealthDataStore
    @EnvironmentObject private var lang: LanguageStore

    @StateObject private var uiState = StatsViewState()
    @Namespace private var scopeNamespace
    @Namespace private var rangeNamespace

    var body: some View {
        let overview = dataStore.overview(forDevice: uiState.selectedDeviceName)
        let records = dataStore.personalRecords(forDevice: uiState.selectedDeviceName)
        let snapshot = dataStore.snapshot(
            for: uiState.selectedRange,
            offset: uiState.periodOffset,
            deviceName: uiState.selectedDeviceName,
            isEnglish: lang.isEnglish
        )

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                deviceScopeBar
                    .staggeredAppear(delay: 0.02)

                totalHeroCard(overview)
                    .staggeredAppear(delay: 0.07)
                    .scrollTransition { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1.0 : 0.96)
                            .opacity(phase.isIdentity ? 1.0 : 0.84)
                    }

                periodChartSection(snapshot)
                    .staggeredAppear(delay: 0.13)
                    .scrollTransition { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1.0 : 0.96)
                            .opacity(phase.isIdentity ? 1.0 : 0.84)
                    }

                personalRecordsGrid(records)
                    .staggeredAppear(delay: 0.19)
                    .scrollTransition { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1.0 : 0.96)
                            .opacity(phase.isIdentity ? 1.0 : 0.84)
                    }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 114)
        }
        .sensoryFeedback(.selection, trigger: uiState.selectedRange)
        .sensoryFeedback(.selection, trigger: uiState.selectedDeviceName)
        .sensoryFeedback(.selection, trigger: uiState.selectedBarLabel)
    }

    private var deviceScopeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                scopePill(title: lang.allScope, isSelected: uiState.selectedDeviceName == nil) {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                        uiState.selectedDeviceName = nil
                        uiState.periodOffset = 0
                        uiState.selectedBarLabel = nil
                    }
                }

                ForEach(dataStore.deviceSummaries) { device in
                    scopePill(title: device.deviceName, isSelected: uiState.selectedDeviceName == device.deviceName) {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                            uiState.selectedDeviceName = device.deviceName
                            uiState.periodOffset = 0
                            uiState.selectedBarLabel = nil
                        }
                    }
                }
            }
            .padding(4)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.04)))
                    .overlay(Capsule().strokeBorder(GlassTheme.glassRimGradient, lineWidth: 1))
            }
        }
    }

    private func scopePill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(GlassTheme.activeBlueGlass)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.36), lineWidth: 1))
                            .shadow(color: GlassTheme.accentBlue.opacity(0.35), radius: 10, x: 0, y: 4)
                            .matchedGeometryEffect(id: "ACTIVE_SCOPE_PILL", in: scopeNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func totalHeroCard(_ overview: UsageOverviewSummary) -> some View {
        let total = DurationFormatter.split(minutes: overview.totalMinutes)
        let daily = DurationFormatter.split(minutes: overview.dailyAverageMinutes)

        return VStack(alignment: .leading, spacing: 18) {
            Text(uiState.selectedDeviceName ?? lang.totalUsage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.56))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(total.hours)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GlassTheme.activeBlueGlass)
                    .contentTransition(.numericText())
                Text("h")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .padding(.trailing, 6)
                Text("\(total.mins)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GlassTheme.activeBlueGlass)
                    .contentTransition(.numericText())
                Text("min")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.52))
            }

            HStack(spacing: 16) {
                Text(lang.daysCount(overview.activeDays))
                    .contentTransition(.numericText())
                Text("·").foregroundStyle(.white.opacity(0.24))
                Text(lang.dailyAvg(hours: daily.hours, mins: daily.mins))
                    .contentTransition(.numericText())
                Text("·").foregroundStyle(.white.opacity(0.24))
                Text(String(format: "%.0f dB", overview.weightedAverageDecibels))
                    .contentTransition(.numericText())
            }
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 28, padding: 24)
    }

    private func periodChartSection(_ snapshot: PeriodUsageSnapshot) -> some View {
        let activePoint = snapshot.chartPoints.first { $0.label == uiState.selectedBarLabel }
        let displayedMinutes = activePoint?.minutes ?? snapshot.totalMinutes
        let split = DurationFormatter.split(minutes: displayedMinutes)

        return VStack(spacing: 16) {
            HStack(spacing: 4) {
                ForEach(StatsTimeRange.allCases) { range in
                    let isSelected = uiState.selectedRange == range
                    Button {
                        Haptics.light()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                            uiState.selectedRange = range
                            uiState.periodOffset = 0
                            uiState.selectedBarLabel = nil
                        }
                    } label: {
                        Text(lang.rangeTitle(range))
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(GlassTheme.activeBlueGlass)
                                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                                        .shadow(color: GlassTheme.accentBlue.opacity(0.32), radius: 10, x: 0, y: 4)
                                        .matchedGeometryEffect(id: "ACTIVE_RANGE_PILL", in: rangeNamespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(GlassTheme.glassRimGradient, lineWidth: 1))

            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    if uiState.selectedRange != .all {
                        Button {
                            Haptics.soft()
                            withAnimation(.snappy) {
                                uiState.periodOffset -= 1
                                uiState.selectedBarLabel = nil
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.78))
                                .frame(width: 30, height: 30)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                    Text(activePoint.map { "\(snapshot.title) · \($0.label)" } ?? snapshot.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                    Spacer()

                    if uiState.selectedRange != .all {
                        Button {
                            Haptics.soft()
                            withAnimation(.snappy) {
                                uiState.periodOffset = min(0, uiState.periodOffset + 1)
                                uiState.selectedBarLabel = nil
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(uiState.periodOffset < 0 ? .white.opacity(0.78) : .white.opacity(0.2))
                                .frame(width: 30, height: 30)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                        .disabled(uiState.periodOffset >= 0)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("\(split.hours)h \(split.mins)min")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Spacer()

                    if activePoint == nil, let delta = snapshot.deltaMinutes {
                        let sign = delta >= 0 ? "+" : "-"
                        Text("\(sign)\(DurationFormatter.hoursMinutes(minutes: abs(delta)))")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(GlassTheme.softBlue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(GlassTheme.accentBlue.opacity(0.18), in: Capsule())
                            .overlay(Capsule().strokeBorder(GlassTheme.softBlue.opacity(0.25), lineWidth: 0.8))
                    }
                }

                Chart(snapshot.chartPoints) { point in
                    let isHighlighted = uiState.selectedBarLabel == nil || uiState.selectedBarLabel == point.label
                    BarMark(
                        x: .value("Time", point.label),
                        y: .value("Hours", point.minutes / 60.0)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: isHighlighted
                                ? [GlassTheme.softBlue, GlassTheme.accentBlue]
                                : [GlassTheme.accentBlue.opacity(0.28), GlassTheme.deepBlue.opacity(0.28)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(8)
                }
                .chartXSelection(value: $uiState.selectedBarLabel)
                .animation(.spring(response: 0.42, dampingFraction: 0.82), value: snapshot.title)
                .animation(.easeInOut(duration: 0.18), value: uiState.selectedBarLabel)
                .chartYAxis {
                    AxisMarks(position: .leading) { val in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Color.white.opacity(0.09))
                        AxisValueLabel {
                            if let h = val.as(Double.self) {
                                Text("\(Int(round(h)))h")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.42))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(height: 170)
            }
            .liquidGlassCard(cornerRadius: 28, padding: 22)
        }
    }

    private func personalRecordsGrid(_ records: PersonalUsageRecords) -> some View {
        let day = DurationFormatter.split(minutes: records.longestDayMinutes)
        let session = DurationFormatter.split(minutes: records.longestSessionMinutes)
        let month = DurationFormatter.split(minutes: records.longestMonthMinutes)

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            recordCell(title: lang.bestDay, value: "\(day.hours)h \(day.mins)m", subtitle: records.longestDayDate.map(formatDotDate) ?? "—")
            recordCell(title: lang.longestSession, value: "\(session.hours)h \(session.mins)m", subtitle: formatSessionRange(start: records.longestSessionStart, end: records.longestSessionEnd))
            recordCell(title: lang.streak, value: lang.daysCount(records.longestStreakDays), subtitle: formatDateSpan(start: records.longestStreakStart, end: records.longestStreakEnd))
            recordCell(title: lang.bestMonth, value: "\(month.hours)h \(month.mins)m", subtitle: records.longestMonthDate.map(formatYearMonth) ?? "—")
        }
    }

    private func recordCell(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.52))
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.40))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 24, padding: 18)
    }

    private func formatDotDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy.MM.dd"
        return f.string(from: date)
    }

    private func formatYearMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: lang.isEnglish ? "en_US" : "zh_CN")
        f.dateFormat = lang.isEnglish ? "MMM yyyy" : "yyyy.MM"
        return f.string(from: date)
    }

    private func formatSessionRange(start: Date?, end: Date?) -> String {
        guard let start, let end else { return "—" }
        let d = DateFormatter(); d.dateFormat = "MM.dd"
        let t = DateFormatter(); t.dateFormat = "HH:mm"
        return "\(d.string(from: start)) \(t.string(from: start))–\(t.string(from: end))"
    }

    private func formatDateSpan(start: Date?, end: Date?) -> String {
        guard let start, let end else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MM.dd"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }
}
