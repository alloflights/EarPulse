import Charts
import SwiftUI

/// 首页概览：当前耳机 3D 动态卡片 + WHO 今日安全额度 + 7 天分贝趋势图
struct DashboardView: View {
    @EnvironmentObject private var healthManager: HealthKitManager
    @EnvironmentObject private var audioMonitor: AudioRouteMonitor

    var onReplayLaunch: () -> Void

    private var currentLevel: ExposureLevel {
        ExposureLevel.from(decibels: healthManager.todayAverageDecibels)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // 1. 数据源状态条
                    dataSourceBanner

                    // 2. 当前耳机 3D 动态贴图主卡片
                    currentHeadphoneHeroCard

                    // 3. WHO 今日听力安全额度卡片
                    whoSafeQuotaCard

                    // 4. 近 7 天耳机分贝趋势图
                    sevenDayChartCard

                    // 5. 高音量通知记录
                    if !healthManager.loudEvents.isEmpty {
                        loudEventsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("聆听概览")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onReplayLaunch()
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel("重播开启动画")
                }
            }
        }
    }

    // MARK: - 数据源与 HealthKit 授权条
    private var dataSourceBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: healthManager.isUsingDemoData ? "wand.and.stars" : "heart.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(healthManager.isUsingDemoData ? .blue : .pink)
                .frame(width: 32, height: 32)
                .background((healthManager.isUsingDemoData ? Color.blue : Color.pink).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(healthManager.isUsingDemoData ? "当前为演示数据" : "已接入 Apple 健康")
                    .font(.subheadline.weight(.semibold))
                Text(healthManager.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if healthManager.isLoading {
                ProgressView()
            } else if healthManager.isUsingDemoData {
                Button("同步健康") {
                    Task {
                        await healthManager.requestHealthKitAuthorizationAndFetch()
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .clipShape(Capsule())
            } else {
                Button("演示模式") {
                    healthManager.switchToDemoMode()
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 当前耳机 3D 贴图卡片
    private var currentHeadphoneHeroCard: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(audioMonitor.isConnected ? Color.green : audioMonitor.connectedCategory.accentColor)
                        .frame(width: 8, height: 8)
                    Text(audioMonitor.portTypeDescription)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(currentLevel.rawValue, systemImage: currentLevel.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(currentLevel.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(currentLevel.color.opacity(0.12), in: Capsule())
            }

            // 居中悬浮耳机贴图 + 声波涟漪
            HeadphoneArtworkView(
                category: audioMonitor.connectedCategory,
                size: 132,
                glowColor: currentLevel.color,
                animateFloating: true,
                showSoundWaves: true
            )
            .frame(height: 156)

            VStack(spacing: 4) {
                Text(audioMonitor.connectedDeviceName)
                    .font(.title3.weight(.bold))
                Text(audioMonitor.connectedCategory.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 今日三项核心数据
            HStack(spacing: 0) {
                metricCell(
                    title: "今日均分贝",
                    value: "\(Int(round(healthManager.todayAverageDecibels)))",
                    unit: "dB",
                    color: currentLevel.color
                )
                Divider().frame(height: 34)
                metricCell(
                    title: "今日峰值",
                    value: "\(Int(round(healthManager.todayPeakDecibels)))",
                    unit: "dB",
                    color: ExposureLevel.from(decibels: healthManager.todayPeakDecibels).color
                )
                Divider().frame(height: 34)
                metricCell(
                    title: "今日佩戴",
                    value: "\(Int(round(healthManager.todayTotalMinutes)))",
                    unit: "分钟",
                    color: .primary
                )
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func metricCell(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text(unit)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - WHO 今日安全声剂量额度环
    private var whoSafeQuotaCard: some View {
        let remaining = healthManager.remainingSafeQuotaPercentage
        let progress = max(0.0, min(1.0, remaining / 100.0))
        let ringColor: Color = remaining >= 50 ? .green : (remaining >= 20 ? .orange : .pink)
        let safeAtCurrent = AcousticDoseCalculator.dailySafeMinutes(at: max(60, healthManager.todayAverageDecibels))

        return HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.16), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [ringColor.opacity(0.75), ringColor],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: progress)

                VStack(spacing: 1) {
                    Text("\(Int(round(remaining)))%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("剩余额度")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 86, height: 86)

            VStack(alignment: .leading, spacing: 6) {
                Text("今日听力安全额度")
                    .font(.headline)
                Text(currentLevel.shortAdvice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("按当前平均音量，每日建议上限约 \(AcousticDoseCalculator.formatSafeDuration(minutes: safeAtCurrent))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(ringColor)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - 近 7 天分贝趋势图
    private var sevenDayChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("近 7 天耳机分贝趋势")
                        .font(.headline)
                    Text("虚线为 80 dB 听觉安全警戒线")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("单位: dB")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Chart {
                RuleMark(y: .value("警戒线", 80))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .foregroundStyle(.orange.opacity(0.8))

                ForEach(healthManager.dailyPoints) { point in
                    BarMark(
                        x: .value("日期", point.weekdayLabel),
                        y: .value("平均分贝", point.averageDecibels)
                    )
                    .foregroundStyle(ExposureLevel.from(decibels: point.averageDecibels).color.gradient)
                    .cornerRadius(7)
                }
            }
            .chartYScale(domain: 40...100)
            .chartYAxis {
                AxisMarks(values: [50, 65, 80, 95])
            }
            .frame(height: 185)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - 高音量警告事件
    private var loudEventsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("近期高音量提醒", systemImage: "bell.badge.waveform.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(healthManager.loudEvents.prefix(3)) { event in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(round(event.decibels))) dB · 持续约 \(Int(round(event.durationMinutes))) 分钟")
                            .font(.subheadline.weight(.semibold))
                        Text(event.date, format: .dateTime.month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("偏高")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
