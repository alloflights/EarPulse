import SwiftUI
import WidgetKit
#if os(iOS)
import HealthKit
#endif

struct EarWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: EarWidgetSnapshot
}

// MARK: - 小组件直连 HealthKit 兜底读取（即使签名证书未配置 App Group 也能直接拉取真实今日数据）
#if os(iOS)
private enum WidgetHealthKitFallback {
    static func fetchLatestSnapshot(completion: @escaping (EarWidgetSnapshot?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let exposureType = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure) else {
            completion(nil)
            return
        }

        let store = HKHealthStore()
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today

        let predicate = HKQuery.predicateForSamples(withStart: weekStart, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: exposureType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, results, _ in
            guard let samples = results as? [HKQuantitySample], !samples.isEmpty else {
                completion(nil)
                return
            }

            let unit = HKUnit.decibelAWeightedSoundPressureLevel()
            let todaySamples = samples.filter { $0.endDate > today && $0.startDate < tomorrow }

            var hourly = Array(repeating: 0.0, count: 24)
            var todaySpans: [(start: Date, end: Date)] = []

            for sample in todaySamples {
                let s = max(sample.startDate, today)
                let e = min(sample.endDate, tomorrow)
                guard e > s else { continue }
                todaySpans.append((s, e))

                var cursor = s
                while cursor < e {
                    let hour = calendar.component(.hour, from: cursor)
                    let hourFloor = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
                    let nextHour = calendar.date(byAdding: .hour, value: 1, to: hourFloor) ?? tomorrow
                    let segEnd = min(e, nextHour)
                    guard segEnd > cursor else { break }
                    let mins = segEnd.timeIntervalSince(cursor) / 60.0
                    if hour >= 0 && hour < 24 && mins > 0 {
                        hourly[hour] = min(60.0, hourly[hour] + mins)
                    }
                    cursor = segEnd
                }
            }

            let todayTotal = mergedMinutes(todaySpans)
            let todayDb = weightedAvgDb(todaySamples, unit: unit)
            let weekDb = weightedAvgDb(samples, unit: unit)

            let latestSample = todaySamples.first ?? samples.first
            let deviceName: String
            if let name = latestSample?.device?.name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                deviceName = name
            } else if let model = latestSample?.device?.model, !model.trimmingCharacters(in: .whitespaces).isEmpty {
                deviceName = model
            } else {
                deviceName = "earuseage"
            }

            completion(
                EarWidgetSnapshot(
                    updatedAt: now,
                    todayTotalMinutes: todayTotal,
                    todayAverageDecibels: todayDb,
                    weekAverageDecibels: weekDb,
                    activeDeviceName: deviceName,
                    hourlyMinutes: hourly
                )
            )
        }
        store.execute(query)
    }

    private static func mergedMinutes(_ spans: [(start: Date, end: Date)]) -> Double {
        let sorted = spans.sorted { $0.start < $1.start }
        guard let first = sorted.first else { return 0 }
        var merged: [(start: Date, end: Date)] = [first]
        for span in sorted.dropFirst() {
            var last = merged[merged.count - 1]
            if span.start <= last.end {
                if span.end > last.end {
                    last.end = span.end
                    merged[merged.count - 1] = last
                }
            } else {
                merged.append(span)
            }
        }
        return merged.reduce(0.0) { $0 + max(0, $1.end.timeIntervalSince($1.start)) / 60.0 }
    }

    private static func weightedAvgDb(_ samples: [HKQuantitySample], unit: HKUnit) -> Double {
        guard !samples.isEmpty else { return 0 }
        var weighted = 0.0
        var total = 0.0
        for s in samples {
            let mins = max(s.endDate.timeIntervalSince(s.startDate) / 60.0, 0.2)
            weighted += s.quantity.doubleValue(for: unit) * mins
            total += mins
        }
        return total > 0 ? weighted / total : 0
    }
}
#endif

struct EarWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> EarWidgetEntry {
        EarWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (EarWidgetEntry) -> Void) {
        if let shared = EarWidgetSnapshot.loadFromSharedStore(), shared.todayTotalMinutes > 0 || shared.weekAverageDecibels > 0 {
            completion(EarWidgetEntry(date: Date(), snapshot: shared))
            return
        }
        if context.isPreview {
            completion(EarWidgetEntry(date: Date(), snapshot: .placeholder))
            return
        }
        #if os(iOS)
        WidgetHealthKitFallback.fetchLatestSnapshot { hkSnap in
            completion(EarWidgetEntry(date: Date(), snapshot: hkSnap ?? .empty))
        }
        #else
        completion(EarWidgetEntry(date: Date(), snapshot: .empty))
        #endif
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EarWidgetEntry>) -> Void) {
        let now = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 20, to: now) ?? now.addingTimeInterval(1200)

        // 1. 优先读取 App Group 共享容器（含 export.xml 导入数据）
        if let shared = EarWidgetSnapshot.loadFromSharedStore(),
           Calendar.current.isDateInToday(shared.updatedAt),
           (shared.todayTotalMinutes > 0 || shared.weekAverageDecibels > 0) {
            let entry = EarWidgetEntry(date: now, snapshot: shared)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
            return
        }

        // 2. 若证书未开启 App Group 或共享数据为空，小组件直接查 Apple HealthKit 兜底
        #if os(iOS)
        WidgetHealthKitFallback.fetchLatestSnapshot { hkSnap in
            let finalSnap = hkSnap ?? EarWidgetSnapshot.loadFromSharedStore() ?? .empty
            let entry = EarWidgetEntry(date: now, snapshot: finalSnap)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
        #else
        let fallback = EarWidgetSnapshot.loadFromSharedStore() ?? .empty
        completion(Timeline(entries: [EarWidgetEntry(date: now, snapshot: fallback)], policy: .after(nextUpdate)))
        #endif
    }
}

// MARK: - 完全透明玻璃背板（与 iOS 26 原生透明液态玻璃小组件一致，透出桌面壁纸，保留彩色强调色）
private struct ClearLiquidGlassWidgetBackdrop: View {
    var body: some View {
        ZStack {
            if #available(iOS 26.0, macOS 26.0, *) {
                Color.clear
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.35)
            }

            ContainerRelativeShape()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.45),
                            Color.white.opacity(0.12),
                            Color(red: 0.30, green: 0.66, blue: 1.0).opacity(0.22),
                            Color.white.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        }
    }
}

// MARK: - 24 小时今日使用频率微柱状图（保留彩色电光蓝强调色）
private struct HourlyFrequencyBars: View {
    let hourlyMinutes: [Double]
    var showAxisLabels: Bool = false

    private let accentBlue = Color(red: 0.24, green: 0.60, blue: 1.0)
    private let softBlue = Color(red: 0.58, green: 0.84, blue: 1.0)

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
                                    : AnyShapeStyle(Color.white.opacity(0.22))
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
                .foregroundStyle(.white.opacity(0.62))
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

// MARK: - 小组件主视图（完全透明玻璃底板 + 彩色强调色，支持小号 2x2 与中号 4x2）
struct EarPulseWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EarWidgetEntry

    private let softBlue = Color(red: 0.58, green: 0.84, blue: 1.0)
    private let accentBlue = Color(red: 0.24, green: 0.60, blue: 1.0)

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
            ClearLiquidGlassWidgetBackdrop()
        }
    }

    private var smallView: some View {
        let split = splitMinutes(entry.snapshot.todayTotalMinutes)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "airpodspro")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accentBlue)
                    .widgetAccentable()
                Text(entry.snapshot.activeDeviceName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
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
                        .foregroundStyle(.white.opacity(0.70))
                    Text("\(split.mins)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("m")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.70))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accentBlue)
                        .widgetAccentable()
                    Text(formatDB(entry.snapshot.todayAverageDecibels))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(softBlue)
                        .widgetAccentable()
                }
            }

            Spacer(minLength: 2)

            HourlyFrequencyBars(hourlyMinutes: entry.snapshot.hourlyMinutes, showAxisLabels: false)
                .frame(height: 36)
                .widgetAccentable()
        }
        .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        let split = splitMinutes(entry.snapshot.todayTotalMinutes)

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "airpodspro")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accentBlue)
                        .widgetAccentable()
                    Text("earuseage")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.80))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(split.hours)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("h")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.70))
                        Text("\(split.mins)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("m")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.70))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                    Text(entry.snapshot.activeDeviceName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

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
                        .fill(accentBlue.opacity(0.32))
                        .overlay(Capsule().strokeBorder(softBlue.opacity(0.45), lineWidth: 0.7))
                )
            }
            .frame(width: 118, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("今日频率")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer()
                    if entry.snapshot.weekAverageDecibels > 0 {
                        Text("7d \(Int(round(entry.snapshot.weekAverageDecibels))) dB")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(softBlue)
                            .widgetAccentable()
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
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7)
                    )
            )
        }
        .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
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
