import Charts
import Combine
import SwiftUI

@MainActor
private final class ScreenTimeStatsState: ObservableObject {
    @Published var selectedDate: Date? = nil
    @Published var tappedWeekday: String? = nil
}

/// 仿 Apple「屏幕时间」布局的统计页：
/// 1. 过去一周每日柱状图 + 虚线「平均」线（点击任意一天可切换查看该日 24 小时明细）
/// 2. 昨天 / 选中日 24 小时逐小时分耳机堆叠柱状图 + 下方各耳机色标图例与时长
struct StatsView: View {
    @EnvironmentObject private var dataStore: HealthDataStore
    @EnvironmentObject private var lang: LanguageStore

    @StateObject private var uiState = ScreenTimeStatsState()

    var body: some View {
        let snapshot = dataStore.screenTimeSnapshot(
            selectedDate: uiState.selectedDate,
            isEnglish: lang.isEnglish
        )

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                weeklyOverviewCard(snapshot)
                    .staggeredAppear(delay: 0.04)

                hourlyDetailCard(snapshot)
                    .staggeredAppear(delay: 0.12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 114)
        }
        .onChange(of: uiState.tappedWeekday) { _, newLabel in
            guard let newLabel,
                  let matched = snapshot.weekBars.first(where: { $0.weekdayLabel == newLabel }) else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                uiState.selectedDate = matched.date
            }
        }
    }

    // MARK: - 1. 过去一周 + 平均虚线卡片
    private func weeklyOverviewCard(_ snapshot: ScreenTimeStatsSnapshot) -> some View {
        let selectedSplit = DurationFormatter.split(minutes: snapshot.selectedDayTotalMinutes)
        let avgHours = snapshot.weekAverageMinutes / 60.0

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(formatDayTitle(snapshot.selectedDate))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(selectedSplit.hours)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("h")
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.trailing, 4)
                        Text("\(selectedSplit.mins)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("min")
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }

                Spacer()

                Text(lang.last7Days)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GlassTheme.softBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(GlassTheme.accentBlue.opacity(0.18), in: Capsule())
            }

            Chart {
                if avgHours > 0.05 {
                    RuleMark(y: .value(lang.avgLabel, avgHours))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(lang.avgLabel)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                }

                ForEach(snapshot.weekBars) { bar in
                    let isSelected = Calendar.current.isDate(bar.date, inSameDayAs: snapshot.selectedDate)
                    BarMark(
                        x: .value("Day", bar.weekdayLabel),
                        y: .value("Hours", bar.totalMinutes / 60.0)
                    )
                    .foregroundStyle(
                        isSelected
                            ? GlassTheme.activeBlueGlass
                            : LinearGradient(
                                colors: [Color.white.opacity(0.28), Color.white.opacity(0.16)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
                    .cornerRadius(7)
                }
            }
            .chartXSelection(value: $uiState.tappedWeekday)
            .chartYAxis {
                AxisMarks(position: .trailing) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Color.white.opacity(0.10))
                    AxisValueLabel {
                        if let h = val.as(Double.self) {
                            Text("\(Int(round(h)))h")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(height: 156)
        }
        .liquidGlassCard(cornerRadius: 28, padding: 22)
    }

    // MARK: - 2. 24 小时逐小时分耳机堆叠柱状图 + 下方分耳机图例（保留空数据防崩溃保护）
    private func hourlyDetailCard(_ snapshot: ScreenTimeStatsSnapshot) -> some View {
        let colorDomain = snapshot.dayBreakdowns.map(\.deviceName)
        let colorRange = snapshot.dayBreakdowns.map { GlassTheme.deviceColor(at: $0.colorIndex) }
        let safeBars = snapshot.hourlyBars.filter { colorDomain.contains($0.deviceName) }

        return VStack(alignment: .leading, spacing: 18) {
            Text(lang.hourlyTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))

            Group {
                if !colorDomain.isEmpty && !safeBars.isEmpty {
                    Chart(safeBars) { slot in
                        BarMark(
                            x: .value("Hour", slot.hour),
                            y: .value("Minutes", slot.minutes),
                            width: .fixed(7)
                        )
                        .foregroundStyle(by: .value("Device", slot.deviceName))
                        .cornerRadius(3)
                    }
                    .chartForegroundStyleScale(domain: colorDomain, range: colorRange)
                    .chartLegend(.hidden)
                } else {
                    Chart {
                        RuleMark(y: .value("Zero", 0))
                            .foregroundStyle(.clear)
                    }
                }
            }
            .chartXScale(domain: 0...23)
            .chartYScale(domain: 0...60)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18]) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Color.white.opacity(0.10))
                    AxisValueLabel {
                        if let h = val.as(Int.self) {
                            Text(lang.isEnglish ? "\(h)h" : "\(h)时")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 30, 60]) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Color.white.opacity(0.10))
                    AxisValueLabel {
                        if let m = val.as(Int.self) {
                            Text(m == 0 ? "0" : "\(m)m")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
            }
            .frame(height: 162)

            if !snapshot.dayBreakdowns.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 22) {
                        ForEach(snapshot.dayBreakdowns) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(GlassTheme.deviceColor(at: item.colorIndex))
                                        .frame(width: 8, height: 8)
                                    Text(item.deviceName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(GlassTheme.deviceColor(at: item.colorIndex))
                                        .lineLimit(1)
                                }
                                Text(DurationFormatter.hoursMinutes(minutes: item.minutes))
                                    .font(.subheadline.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .liquidGlassCard(cornerRadius: 28, padding: 22)
    }

    private func formatDayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInYesterday(date) {
            let f = DateFormatter()
            f.dateFormat = lang.isEnglish ? "MMM d" : "M月d日"
            return "\(f.string(from: date)) · \(lang.yesterday)"
        }
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = lang.isEnglish ? "MMM d" : "M月d日"
            return "\(f.string(from: date)) · \(lang.isEnglish ? "Today" : "今天")"
        }
        let f = DateFormatter()
        f.dateFormat = lang.isEnglish ? "MMM d" : "M月d日"
        return f.string(from: date)
    }
}
