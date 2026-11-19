import Charts
import SwiftUI

/// 多耳机区分与对比视图：按每款耳机展示累计使用时间、占比、活跃天数、单次最长与分贝护耳评分
struct DevicesView: View {
    @EnvironmentObject private var healthManager: HealthKitManager
    @EnvironmentObject private var audioMonitor: AudioRouteMonitor

    var onSelectDevicePreview: () -> Void
    @State private var inspectedDevice: HeadphoneUsageSummary?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // 1. 多耳机护耳洞察
                    insightCard

                    // 2. 每款耳机累计使用时间对比图
                    if healthManager.deviceSummaries.count >= 2 {
                        usageHoursComparisonChartCard
                    }

                    // 3. 逐设备详细使用时间与分贝档案列表
                    VStack(alignment: .leading, spacing: 12) {
                        Text("每款耳机使用时间与档案 (\(healthManager.deviceSummaries.count))")
                            .font(.headline)
                            .padding(.horizontal, 4)

                        ForEach(healthManager.deviceSummaries) { summary in
                            deviceCard(summary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("我的耳机")
            .sheet(item: $inspectedDevice) { device in
                DevicePopupPreviewSheet(device: device) {
                    audioMonitor.selectPreviewHeadphone(name: device.deviceName, category: device.category)
                    inspectedDevice = nil
                    onSelectDevicePreview()
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var insightCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.max.fill")
                .font(.title3)
                .foregroundStyle(.teal)
                .padding(10)
                .background(Color.teal.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text("多耳机护耳洞察")
                    .font(.subheadline.weight(.bold))
                Text(healthManager.multiDeviceInsight)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var usageHoursComparisonChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("每款耳机累计佩戴时长对比")
                .font(.headline)

            Chart(healthManager.deviceSummaries) { item in
                BarMark(
                    x: .value("累计小时", item.totalMinutes / 60.0),
                    y: .value("耳机", item.deviceName)
                )
                .foregroundStyle(item.category.accentColor.gradient)
                .cornerRadius(6)
                .annotation(position: .trailing) {
                    Text(item.formattedDuration)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: CGFloat(max(140, healthManager.deviceSummaries.count * 44)))
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func deviceCard(_ summary: HeadphoneUsageSummary) -> some View {
        let isActive = audioMonitor.connectedDeviceName == summary.deviceName

        return Button {
            inspectedDevice = summary
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    HeadphoneArtworkView(
                        category: summary.category,
                        size: 62,
                        glowColor: summary.category.accentColor,
                        animateFloating: false,
                        showSoundWaves: false
                    )
                    .frame(width: 72, height: 72)
                    .background(summary.category.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(summary.deviceName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if isActive {
                                Text("当前展示")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(summary.category.accentColor, in: Capsule())
                            }
                        }

                        // 突出每款耳机累计使用时间
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(summary.formattedDuration)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(summary.category.accentColor)
                            Text("· 占比 \(Int(round(summary.sharePercentage)))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Label("\(Int(round(summary.averageDecibels))) dB 均值", systemImage: "waveform")
                            Label("活跃 \(summary.activeDays) 天", systemImage: "calendar")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                // 底部次级数据条：单次最长 + 护耳评分
                HStack {
                    Text("单次最长 \(DurationFormatter.hoursMinutes(minutes: summary.longestSessionMinutes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("护耳分 \(summary.earHealthScore)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(summary.level.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(summary.level.color.opacity(0.12), in: Capsule())
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 仿 AirPods 弹窗风格的耳机 3D 详情预览弹窗
private struct DevicePopupPreviewSheet: View {
    let device: HeadphoneUsageSummary
    let onSetActive: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer().frame(height: 6)

            Text(device.deviceName)
                .font(.title3.weight(.bold))

            HeadphoneArtworkView(
                category: device.category,
                size: 140,
                glowColor: device.level.color,
                animateFloating: true,
                showSoundWaves: true
            )
            .frame(height: 162)

            HStack(spacing: 22) {
                VStack(spacing: 4) {
                    Text(device.formattedDuration)
                        .font(.headline.bold())
                        .foregroundStyle(device.category.accentColor)
                    Text("累计佩戴")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    Text("\(Int(round(device.averageDecibels))) dB")
                        .font(.headline.bold())
                        .foregroundStyle(device.level.color)
                    Text("平均分贝")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    Text("\(device.activeDays) 天")
                        .font(.headline.bold())
                    Text("活跃天数")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                onSetActive()
            } label: {
                Text("在首页以该耳机贴图展示")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(device.category.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding()
    }
}
