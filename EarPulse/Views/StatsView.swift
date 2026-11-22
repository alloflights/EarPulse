import Charts
import Combine
import SwiftUI

@MainActor
private final class ScreenTimeStatsState: ObservableObject {
    @Published var selectedDate: Date? = nil
}

/// 仿 Apple「屏幕时间」布局的统计页：
/// 1. 过去一周每日柱状图 + 虚线「平均」线（单击即时切换，带滑动背光与蓝色柱条平滑过渡动效）
/// 2. 昨天 / 选中日 24 小时逐小时分耳机堆叠柱状图 + 下方各耳机色标图例与平均分贝
struct StatsView: View {
    @EnvironmentObject private var dataStore: HealthDataStore
    @EnvironmentObject private var lang: LanguageStore

    @StateObject private var uiState = ScreenTimeStatsState()
    @Namespace private var weekBarNamespace

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
    }

    // MARK: - 1. 过去一周 + 平均虚线卡片（轻点即切 + 蓝色柱条滑动背光与渐显弹簧动效）
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

                VStack(alignment: .trailing, spacing: 5) {
                    Text(lang.last7Days)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GlassTheme.softBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(GlassTheme.accentBlue.opacity(0.18), in: Capsule())

                    if snapshot.weekAverageMinutes > 0 {
                        let avgSplit = DurationFormatter.split(minutes: snapshot.weekAverageMinutes)
                        Text(lang.dailyAvg(hours: avgSplit.hours, mins: avgSplit.mins))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }

            Chart {
                if avgHours > 0.05 {
                    let avgSplit = DurationFormatter.split(minutes: snapshot.weekAverageMinutes)
                    RuleMark(y: .value(lang.avgLabel, avgHours))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("\(lang.avgLabel) \(avgSplit.hours)h \(avgSplit.mins)m")
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.68))
                        }
                }

                // 底层磨砂灰柱（始终存在）
                ForEach(snapshot.weekBars) { bar in
                    BarMark(
                        x: .value("Day", bar.weekdayLabel),
                        y: .value("Hours", bar.totalMinutes / 60.0),
                        stacking: .unstacked
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(7)
                }

                // 顶层蓝光选中柱（通过 opacity 平滑淡入淡出，避免 LinearGradient 硬切无动效）
                ForEach(snapshot.weekBars) { bar in
                    let isSelected = Calendar.current.isDate(bar.date, inSameDayAs: snapshot.selectedDate)
                    BarMark(
                        x: .value("Day", bar.weekdayLabel),
                        y: .value("Hours", bar.totalMinutes / 60.0),
                        stacking: .unstacked
                    )
                    .foregroundStyle(GlassTheme.activeBlueGlass)
                    .opacity(isSelected ? 1.0 : 0.0)
                    .cornerRadius(7)
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: snapshot.selectedDate)
            // 选中列滑动背光柱（matchedGeometryEffect 横向弹性滑移）
            .chartBackground { proxy in
                GeometryReader { geo in
                    let plotFrame = proxy.plotFrame.map { geo[$0] } ?? geo.frame(in: .local)
                    HStack(spacing: 0) {
                        ForEach(snapshot.weekBars) { bar in
                            let isSelected = Calendar.current.isDate(bar.date, inSameDayAs: snapshot.selectedDate)
                            ZStack {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    GlassTheme.accentBlue.opacity(0.18),
                                                    GlassTheme.accentBlue.opacity(0.05),
                                                    Color.clear
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .padding(.horizontal, 3)
                                        .matchedGeometryEffect(id: "WEEK_SELECTED_COLUMN", in: weekBarNamespace)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: plotFrame.width, height: plotFrame.height)
                    .position(x: plotFrame.midX, y: plotFrame.midY)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let plotFrame = proxy.plotFrame.map { geo[$0] } ?? geo.frame(in: .local)
                            let relX = location.x - plotFrame.origin.x
                            guard relX >= 0, relX <= plotFrame.width else { return }

                            if let label: String = proxy.value(atX: relX),
                               let matched = snapshot.weekBars.first(where: { $0.weekdayLabel == label }) {
                                selectDay(matched.date)
                            } else if !snapshot.weekBars.isEmpty {
                                let idx = min(
                                    snapshot.weekBars.count - 1,
                                    max(0, Int((relX / max(1, plotFrame.width)) * CGFloat(snapshot.weekBars.count)))
                                )
                                selectDay(snapshot.weekBars[idx].date)
                            }
                        }
                }
            }
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

            // 今日平均噪音 & 本周平均噪音紧凑双栏
            HStack(spacing: 12) {
                noiseMiniPill(title: lang.todayAvgNoise, decibels: snapshot.todayAverageDecibels)
                noiseMiniPill(title: lang.weekAvgNoise, decibels: snapshot.weekAverageDecibels)
            }
            .padding(.top, 2)
        }
        .liquidGlassCard(cornerRadius: 28, padding: 22)
    }

    private func noiseMiniPill(title: String, decibels: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(GlassTheme.softBlue)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(decibels > 0 ? "\(Int(round(decibels))) dB" : "-- dB")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func selectDay(_ date: Date) {
        if let current = uiState.selectedDate, Calendar.current.isDate(current, inSameDayAs: date) {
            return
        }
        Haptics.selection()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            uiState.selectedDate = date
        }
    }

    // MARK: - 2. 24 小时逐小时分耳机堆叠柱状图 + 下方分耳机图例与平均分贝
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
            .animation(.spring(response: 0.36, dampingFraction: 0.80), value: snapshot.selectedDate)
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
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(DurationFormatter.hoursMinutes(minutes: item.minutes))
                                        .font(.subheadline.weight(.bold))
                                        .monospacedDigit()
                                        .foregroundStyle(.white)
                                        .contentTransition(.numericText())
                                    if item.averageDecibels > 0 {
                                        Text("\(Int(round(item.averageDecibels))) dB")
                                            .font(.caption2.weight(.semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(GlassTheme.softBlue.opacity(0.85))
                                    }
                                }
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
