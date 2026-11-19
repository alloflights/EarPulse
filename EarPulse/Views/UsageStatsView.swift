import Charts
import SwiftUI

/// 核心「统计与使用时间分析」页面：
/// 复刻深色网格极简风格，包含杂志风使用时间总结、个人纪录 2x2 网格、最常戴耳机、周/月/年/总共切换、每款耳机使用时间与 24 小时时段分析
struct UsageStatsView: View {
    @EnvironmentObject private var healthManager: HealthKitManager
    @State private var selectedRange: StatsTimeRange = .week
    @State private var periodOffset: Int = 0

    private let iceBlue = Color(red: 0.58, green: 0.75, blue: 0.99)
    private let cardBackground = Color(white: 0.14).opacity(0.86)
    private let cardBorder = Color.white.opacity(0.08)

    var body: some View {
        let analysis = healthManager.usageAnalysis
        let records = healthManager.personalRecords
        let snapshot = healthManager.snapshot(for: selectedRange, offset: periodOffset)

        NavigationStack {
            ZStack {
                BlueprintGridBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // 1. 顶部标题区
                        HStack(alignment: .firstTextBaseline) {
                            Text("统计")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(.white)
                            Spacer()
                            Text(healthManager.isUsingDemoData ? "演示历史" : "已读取历史")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        }

                        // 2. 杂志风「使用时间深度分析」主卡片（对标参考图 2）
                        editorialAnalysisCard(analysis)

                        // 3. 个人纪录 2x2 网格（对标参考图 1）
                        personalRecordsSection(records)

                        // 4. 最常戴耳机大卡片（对标参考图 1）
                        if let topDevice = healthManager.mostUsedDevice {
                            mostUsedHeadphoneCard(topDevice)
                        }

                        // 5. 周 / 月 / 年 / 总共 周期统计 + 累计时长同比 + 每款耳机使用时间
                        periodUsageSection(snapshot)

                        // 6. 24 小时使用时段分析（深夜伴眠 / 上午通勤 / 午后专注 / 夜间放松）
                        timeOfDayAnalysisSection(analysis)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .preferredColorScheme(.dark)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - 1. 杂志风使用时间总结卡片
    private func editorialAnalysisCard(_ analysis: UsageTimeAnalysis) -> some View {
        let totalSplit = DurationFormatter.splitHoursMinutes(minutes: analysis.mergedTotalMinutes)
        let dailySplit = DurationFormatter.splitHoursMinutes(minutes: analysis.dailyAverageMinutes)

        return VStack(alignment: .leading, spacing: 16) {
            Text(analysis.headline)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if let first = analysis.firstDate, let last = analysis.lastDate {
                Text("基于 Apple 健康读取的 \(analysis.rawSampleCount.formatted()) 条「耳机音频水平」原始记录（\(formatChineseDate(first)) 至 \(formatChineseDate(last))），按时间区间去重合并后统计。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineSpacing(3)
            }

            // 醒目冰蓝大数字：XXX h XX min
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(totalSplit.hours)")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(iceBlue)
                Text("h")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.trailing, 4)
                Text("\(totalSplit.mins)")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(iceBlue)
                Text("min")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("覆盖 \(analysis.activeDays) 个活跃天（占总跨度 \(String(format: "%.1f", analysis.activeCoveragePercent))%）")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.86))

                Text("日均佩戴 \(dailySplit.hours) h \(dailySplit.mins) min · 时间加权平均音量 \(String(format: "%.1f", analysis.weightedAverageDecibels)) dBASPL")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    // MARK: - 2. 个人纪录 2x2 网格
    private func personalRecordsSection(_ records: PersonalUsageRecords) -> some View {
        let daySplit = DurationFormatter.splitHoursMinutes(minutes: records.longestDayMinutes)
        let sessionSplit = DurationFormatter.splitHoursMinutes(minutes: records.longestSessionMinutes)
        let monthSplit = DurationFormatter.splitHoursMinutes(minutes: records.longestMonthMinutes)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("个人纪录")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("已读取历史")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                recordGridCard(
                    icon: "sun.max",
                    title: "单日佩戴最长",
                    primaryNumber: "\(daySplit.hours)",
                    primaryUnit: "h",
                    secondaryNumber: "\(daySplit.mins)",
                    secondaryUnit: "min",
                    footnote: records.longestDayDate.map { formatDotDate($0) } ?? "—"
                )

                recordGridCard(
                    icon: "timer",
                    title: "单次佩戴最长",
                    primaryNumber: "\(sessionSplit.hours)",
                    primaryUnit: "h",
                    secondaryNumber: "\(sessionSplit.mins)",
                    secondaryUnit: "min",
                    footnote: formatSessionSpan(start: records.longestSessionStart, end: records.longestSessionEnd)
                )

                recordGridCard(
                    icon: "calendar.badge.checkmark",
                    title: "连续记录最长",
                    primaryNumber: "\(records.longestStreakDays)",
                    primaryUnit: " 天",
                    secondaryNumber: nil,
                    secondaryUnit: nil,
                    footnote: formatDateRange(start: records.longestStreakStart, end: records.longestStreakEnd)
                )

                recordGridCard(
                    icon: "calendar",
                    title: "单月佩戴最长",
                    primaryNumber: "\(monthSplit.hours)",
                    primaryUnit: "h",
                    secondaryNumber: "\(monthSplit.mins)",
                    secondaryUnit: "min",
                    footnote: records.longestMonthDate.map { formatYearMonth($0) } ?? "—"
                )
            }
        }
    }

    private func recordGridCard(
        icon: String,
        title: String,
        primaryNumber: String,
        primaryUnit: String,
        secondaryNumber: String?,
        secondaryUnit: String?,
        footnote: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iceBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(primaryNumber)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(primaryUnit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))

                if let sec = secondaryNumber, let secUnit = secondaryUnit {
                    Text(sec)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.leading, 3)
                    Text(secUnit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    // MARK: - 3. 最常戴耳机大卡片
    private func mostUsedHeadphoneCard(_ device: HeadphoneUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "headphones")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iceBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("最常戴耳机")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            HStack(spacing: 16) {
                HeadphoneArtworkView(
                    category: device.category,
                    size: 76,
                    glowColor: device.category.accentColor,
                    animateFloating: false,
                    showSoundWaves: false
                )
                .frame(width: 82, height: 82)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(device.deviceName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(device.hoursPart)")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(iceBlue)
                        Text("h")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.trailing, 4)
                        Text("\(device.minutesPart)")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(iceBlue)
                        Text("min")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Text("已读取历史累计佩戴 · 占比 \(Int(round(device.sharePercentage)))%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    // MARK: - 4. 周 / 月 / 年 / 总共 周期切换 + 每款耳机使用时间
    private func periodUsageSection(_ snapshot: PeriodUsageSnapshot) -> some View {
        let totalSplit = DurationFormatter.splitHoursMinutes(minutes: snapshot.totalMinutes)

        return VStack(spacing: 14) {
            // 分段选择器：周 | 月 | 年 | 总共
            HStack(spacing: 4) {
                ForEach(StatsTimeRange.allCases) { range in
                    let isSelected = selectedRange == range
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedRange = range
                            periodOffset = 0
                        }
                    } label: {
                        Text(range.rawValue)
                            .font(.subheadline.weight(isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                isSelected ? Color.white.opacity(0.18) : Color.clear,
                                in: Capsule()
                            )
                    }
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.08), in: Capsule())

            // 日期翻页条（总共模式不翻页）
            HStack {
                if selectedRange != .all {
                    Button {
                        withAnimation { periodOffset -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 32, height: 32)
                    }
                }
                Spacer()
                Text(snapshot.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if selectedRange != .all {
                    Button {
                        withAnimation { periodOffset = min(0, periodOffset + 1) }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(periodOffset < 0 ? .white.opacity(0.75) : .white.opacity(0.2))
                            .frame(width: 32, height: 32)
                    }
                    .disabled(periodOffset >= 0)
                }
            }

            // 累计佩戴时长 + 较上期变化 + 柱状图
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("累计佩戴时长", systemImage: "clock")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.68))

                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(totalSplit.hours)")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("h")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.trailing, 3)
                            Text("\(totalSplit.mins)")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("min")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }

                    Spacer()

                    if let delta = snapshot.deltaMinutes {
                        let isUp = delta >= 0
                        let absMins = Int(round(abs(delta)))
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("较上期同期")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.55))
                            Text("\(isUp ? "+" : "-")\(DurationFormatter.hoursMinutes(minutes: Double(absMins)))")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(isUp ? iceBlue : .teal)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        }
                    }
                }

                // 时长柱状分布图
                Chart(snapshot.chartPoints) { point in
                    BarMark(
                        x: .value("时段", point.label),
                        y: .value("小时", point.minutes / 60.0)
                    )
                    .foregroundStyle(iceBlue.gradient)
                    .cornerRadius(6)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Color.white.opacity(0.12))
                        AxisValueLabel {
                            if let h = value.as(Double.self) {
                                Text("\(Int(round(h)))h")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.5))
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
                .frame(height: 155)
            }
            .padding(18)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(cardBorder, lineWidth: 1)
            )

            // 每款耳机在该周期的使用时间明细（用户重点要求！）
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("每款耳机使用时间")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(snapshot.deviceSummaries.count) 款设备")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }

                if snapshot.deviceSummaries.isEmpty {
                    Text("当前时间段内暂无耳机佩戴记录")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.vertical, 12)
                } else {
                    ForEach(snapshot.deviceSummaries) { device in
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                HeadphoneArtworkView(
                                    category: device.category,
                                    size: 44,
                                    glowColor: device.category.accentColor,
                                    animateFloating: false,
                                    showSoundWaves: false
                                )
                                .frame(width: 48, height: 48)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.deviceName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text("均值 \(Int(round(device.averageDecibels))) dB · 活跃 \(device.activeDays) 天")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.55))
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(device.formattedDuration)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(iceBlue)
                                    Text("\(Int(round(device.sharePercentage)))%")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }

                            // 占比进度条
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.08))
                                    Capsule()
                                        .fill(device.category.accentColor.gradient)
                                        .frame(width: max(6, geo.size.width * CGFloat(device.sharePercentage / 100.0)))
                                }
                            }
                            .frame(height: 6)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(18)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(cardBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - 5. 24 小时佩戴时段分析
    private func timeOfDayAnalysisSection(_ analysis: UsageTimeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("使用时间时段分析")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("24 小时分布")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            ForEach(analysis.timeOfDayBuckets) { bucket in
                VStack(spacing: 6) {
                    HStack {
                        Label(bucket.title, systemImage: bucket.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(bucket.timeRangeText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer()
                        Text("\(DurationFormatter.hoursMinutes(minutes: bucket.minutes)) (\(Int(round(bucket.share * 100)))%)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(bucket.color)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(bucket.color.gradient)
                                .frame(width: max(6, geo.size.width * CGFloat(bucket.share)))
                        }
                    }
                    .frame(height: 7)
                }
            }

            Text(analysis.habitSummary)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(3)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(18)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    // MARK: - 日期格式化辅助
    private func formatChineseDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }

    private func formatDotDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: date)
    }

    private func formatYearMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy 年 M 月"
        return f.string(from: date)
    }

    private func formatSessionSpan(start: Date?, end: Date?) -> String {
        guard let start, let end else { return "—" }
        let dFmt = DateFormatter()
        dFmt.dateFormat = "yyyy.M.d"
        let tFmt = DateFormatter()
        tFmt.dateFormat = "HH:mm"
        return "\(dFmt.string(from: start)) \(tFmt.string(from: start)) – \(tFmt.string(from: end))"
    }

    private func formatDateRange(start: Date?, end: Date?) -> String {
        guard let start, let end else { return "—" }
        return "\(formatDotDate(start)) – \(formatDotDate(end))"
    }
}

/// 复刻参考图的深邃极细网格质感背景
struct BlueprintGridBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.09),
                    Color(red: 0.02, green: 0.03, blue: 0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Canvas { context, size in
                let spacing: CGFloat = 24
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                context.stroke(path, with: .color(Color.white.opacity(0.035)), lineWidth: 0.6)
            }
        }
    }
}
