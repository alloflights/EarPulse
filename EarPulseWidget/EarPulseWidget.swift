import SwiftUI
import WidgetKit

struct EarWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: EarWidgetSnapshot
}

struct EarWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> EarWidgetEntry {
        EarWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (EarWidgetEntry) -> Void) {
        let snap = context.isPreview
            ? (EarWidgetSnapshot.loadFromSharedStore() ?? .placeholder)
            : (EarWidgetSnapshot.loadFromSharedStore() ?? .empty)
        completion(EarWidgetEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EarWidgetEntry>) -> Void) {
        let now = Date()
        let snap = EarWidgetSnapshot.loadFromSharedStore() ?? .empty
        let entry = EarWidgetEntry(date: now, snapshot: snap)
        // 每 30 分钟自动刷新一次时间线，同时主 App 同步时也会立即触发 reloadAllTimelines
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - 玻璃质感小组件背板
private struct WidgetGlassBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.05, green: 0.14, blue: 0.34), location: 0.0),
                    .init(color: Color(red: 0.02, green: 0.06, blue: 0.17), location: 0.55),
                    .init(color: Color(red: 0.01, green: 0.03, blue: 0.09), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 玻璃折射柔光斑
            RadialGradient(
                colors: [
                    Color(red: 0.38, green: 0.72, blue: 1.0).opacity(0.32),
                    Color(red: 0.18, green: 0.48, blue: 0.96).opacity(0.10),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 4,
                endRadius: 180
            )

            RadialGradient(
                colors: [
                    Color(red: 0.24, green: 0.59, blue: 1.0).opacity(0.20),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 4,
                endRadius: 150
            )

            // 玻璃高光微雾层
            LinearGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.white.opacity(0.03),
                    Color.clear,
                    Color.white.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay(
            ContainerRelativeShape()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.45),
                            Color.white.opacity(0.10),
                            Color(red: 0.35, green: 0.68, blue: 1.0).opacity(0.28),
                            Color.white.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - 24 小时今日使用频率微柱状图
private struct HourlyFrequencyBars: View {
    let hourlyMinutes: [Double]
    var showAxisLabels: Bool = false

    private let accentBlue = Color(red: 0.26, green: 0.62, blue: 1.0)
    private let softBlue = Color(red: 0.62, green: 0.85, blue: 1.0)

    var body: some View {
        let slots = normalizedSlots
        let peak = max(30.0, slots.max() ?? 30.0)

        VStack(spacing: 4) {
            GeometryReader { geo in
                let barSpacing: CGFloat = showAxisLabels ? 2.5 : 1.5
                let totalSpacing = barSpacing * CGFloat(max(0, slots.count - 1))
                let barWidth = max(2, (geo.size.width - totalSpacing) / CGFloat(slots.count))

                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, mins in
                        let ratio = min(1.0, max(0.0, mins / peak))
                        let barHeight = mins > 0.2 ? max(4, geo.size.height * CGFloat(ratio)) : 2.5

                        RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                            .fill(
                                mins > 0.2
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [softBlue, accentBlue],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    : AnyShapeStyle(Color.white.opacity(0.14))
                            )
                            .frame(width: barWidth, height: barHeight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }

            if showAxisLabels {
                HStack {
                    Text("0h")
                    Spacer()
                    Text("6h")
                    Spacer()
                    Text("12h")
                    Spacer()
                    Text("18h")
                    Spacer()
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var normalizedSlots: [Double] {
        if hourlyMinutes.count == 24 { return hourlyMinutes }
        var padded = Array(repeating: 0.0, count: 24)
        for i in 0..<min(24, hourlyMinutes.count) {
            padded[i] = hourlyMinutes[i]
        }
        return padded
    }
}

// MARK: - 小组件主视图（支持小号 2x2 与中号 4x2）
struct EarPulseWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EarWidgetEntry

    private let softBlue = Color(red: 0.62, green: 0.85, blue: 1.0)
    private let accentBlue = Color(red: 0.26, green: 0.62, blue: 1.0)

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumView
            default:
                smallView
            }
        }
        .containerBackground(for: .widget) {
            WidgetGlassBackdrop()
        }
    }

    private var smallView: some View {
        let split = splitMinutes(entry.snapshot.todayTotalMinutes)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "airpodspro")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(softBlue)
                    .widgetAccentable()
                Text(entry.snapshot.activeDeviceName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(split.hours)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("h")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("\(split.mins)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("m")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(softBlue)
                        .widgetAccentable()
                    Text(formatDB(entry.snapshot.todayAverageDecibels))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(softBlue)
                }
            }

            Spacer(minLength: 2)

            HourlyFrequencyBars(hourlyMinutes: entry.snapshot.hourlyMinutes, showAxisLabels: false)
                .frame(height: 36)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        let split = splitMinutes(entry.snapshot.todayTotalMinutes)

        return HStack(spacing: 14) {
            // 左侧：今日时长 + 今日平均分贝 + 当前耳机
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "airpodspro")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(softBlue)
                        .widgetAccentable()
                    Text("earuseage")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(split.hours)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("h")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                        Text("\(split.mins)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("m")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                    Text(entry.snapshot.activeDeviceName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                // 今日平均分贝玻璃胶囊
                HStack(spacing: 5) {
                    Image(systemName: "waveform")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(softBlue)
                        .widgetAccentable()
                    Text(formatDB(entry.snapshot.todayAverageDecibels))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(accentBlue.opacity(0.22))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
                )
            }
            .frame(width: 118, alignment: .leading)

            // 右侧：今日 24 小时使用频率柱状图玻璃面板
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("今日频率")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                    Spacer()
                    if entry.snapshot.weekAverageDecibels > 0 {
                        Text("7d \(Int(round(entry.snapshot.weekAverageDecibels))) dB")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(softBlue.opacity(0.85))
                    }
                }

                HourlyFrequencyBars(hourlyMinutes: entry.snapshot.hourlyMinutes, showAxisLabels: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .widgetAccentable()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7)
                    )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func splitMinutes(_ minutes: Double) -> (hours: Int, mins: Int) {
        let total = max(0, Int(round(minutes)))
        return (total / 60, total % 60)
    }

    private func formatDB(_ db: Double) -> String {
        db > 0 ? "\(Int(round(db))) dB" : "-- dB"
    }
}

struct EarPulseWidget: Widget {
    let kind: String = "EarPulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EarWidgetProvider()) { entry in
            EarPulseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("earuseage")
        .description("今日耳机使用频率与平均分贝")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct EarPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        EarPulseWidget()
    }
}
