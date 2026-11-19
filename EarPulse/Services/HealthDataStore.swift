import Combine
import Foundation
#if os(iOS)
import HealthKit
#endif

/// 100% 真实数据存储与同步引擎：支持 iOS HealthKit 实时读取与跨平台 export.xml 一次导入永久缓存
@MainActor
final class HealthDataStore: ObservableObject {
    @Published var samples: [AudioExposureSample] = []
    @Published var deviceSummaries: [HeadphoneUsageSummary] = []

    @Published var isLoading: Bool = false
    @Published var dataSourceLabel: String = ""
    @Published var errorMessage: String?

    #if os(iOS)
    private let healthStore = HKHealthStore()
    #endif
    private let defaults = UserDefaults.standard
    private let hkConnectedKey = "earphone_useage_hk_connected"
    private let sourceLabelKey = "earphone_useage_source_label"

    private var cacheFileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("earphone_useage_real_cache.json")
    }

    var hasRealData: Bool {
        !samples.isEmpty
    }

    var mostUsedDevice: HeadphoneUsageSummary? {
        deviceSummaries.first
    }

    init() {
        loadCachedSamples()
        if let savedLabel = defaults.string(forKey: sourceLabelKey) {
            dataSourceLabel = savedLabel
        }
    }

    func bootstrapOnLaunch() async {
        #if os(iOS)
        if defaults.bool(forKey: hkConnectedKey) {
            await fetchFromHealthKit(silent: true)
        }
        #elseif os(macOS)
        if !hasRealData {
            loadMacPreviewOnlyData()
        }
        #endif
    }

    func connectAppleHealth() async {
        errorMessage = nil
        #if os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "HealthKit unavailable — import export.xml"
            return
        }
        guard let exposureType = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure) else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [exposureType])
            defaults.set(true, forKey: hkConnectedKey)
            await fetchFromHealthKit(silent: false)
        } catch {
            errorMessage = error.localizedDescription
        }
        #else
        errorMessage = "Mac 预览模式请点下方导入 export.xml"
        #endif
    }

    #if os(iOS)
    func fetchFromHealthKit(silent: Bool) async {
        guard HKHealthStore.isHealthDataAvailable(),
              let exposureType = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure) else {
            return
        }

        if !silent { isLoading = true }
        defer { if !silent { isLoading = false } }

        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .year, value: -5, to: endDate) ?? Date.distantPast
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        do {
            let rawSamples = try await queryQuantitySamples(type: exposureType, predicate: predicate)
            let unit = HKUnit.decibelAWeightedSoundPressureLevel()

            let mapped: [AudioExposureSample] = rawSamples.map { sample in
                let db = sample.quantity.doubleValue(for: unit)
                let deviceName = Self.resolveDeviceName(from: sample)
                return AudioExposureSample(
                    id: sample.uuid,
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    decibels: db,
                    deviceName: deviceName,
                    category: HeadphoneCategory.infer(from: deviceName)
                )
            }

            if !mapped.isEmpty {
                applyAndPersist(mapped, source: "Apple Health")
                errorMessage = nil
            } else if !silent && samples.isEmpty {
                errorMessage = "No headphone records found"
            }
        } catch {
            if !silent {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func queryQuantitySamples(type: HKQuantityType, predicate: NSPredicate) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    private static func resolveDeviceName(from sample: HKQuantitySample) -> String {
        if let name = sample.device?.name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        if let model = sample.device?.model, !model.trimmingCharacters(in: .whitespaces).isEmpty {
            return model
        }
        let source = sample.sourceRevision.source.name
        return source.isEmpty ? "Headphones" : source
    }
    #endif

    func importHealthExportXML(from url: URL) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let parsed = try await Task.detached(priority: .userInitiated) {
                try HealthExportXMLParser.parse(fileURL: url)
            }.value

            if parsed.isEmpty {
                errorMessage = "No headphone exposure records in XML"
            } else {
                applyAndPersist(parsed, source: "export.xml")
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if os(macOS)
    /// 仅限 Mac 本机预览使用的内存测试数据（通过 #if os(macOS) 隔离，绝不会编进 iOS .ipa 包）
    func loadMacPreviewOnlyData() {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        var list: [AudioExposureSample] = []

        let devices: [(name: String, category: HeadphoneCategory, baseDb: Double)] = [
            ("CliQueY's AirPods Pro", .airPodsPro, 63.0),
            ("AirPods Max", .airPodsMax, 60.5),
            ("Sony WH-1000XM5", .overEar, 66.0),
            ("In-Ear Monitor", .inEar, 71.0)
        ]

        for dayOffset in 0..<120 {
            if dayOffset == 38 || dayOffset == 84 { continue }
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart) else { continue }

            // 夜间
            if let s1 = calendar.date(byAdding: .minute, value: 40, to: day), s1 < now {
                let dur: Double = (dayOffset == 19) ? 265 : Double(75 + (dayOffset * 13) % 65)
                let e1 = min(now, s1.addingTimeInterval(dur * 60))
                if e1 > s1 {
                    list.append(AudioExposureSample(id: UUID(), startDate: s1, endDate: e1, decibels: 61.5, deviceName: devices[0].name, category: devices[0].category))
                }
            }
            // 白天
            if let s2 = calendar.date(byAdding: .hour, value: 14, to: day), s2 < now {
                let pick = devices[(dayOffset % 3 == 0) ? 1 : ((dayOffset % 3 == 1) ? 2 : 3)]
                let dur: Double = (dayOffset == 10) ? 210 : Double(52 + (dayOffset * 7) % 58)
                let e2 = min(now, s2.addingTimeInterval(dur * 60))
                if e2 > s2 {
                    list.append(AudioExposureSample(id: UUID(), startDate: s2, endDate: e2, decibels: pick.baseDb, deviceName: pick.name, category: pick.category))
                }
            }
        }

        let sorted = list.sorted { $0.startDate > $1.startDate }
        samples = sorted
        deviceSummaries = buildDeviceSummaries(from: sorted)
        errorMessage = nil
    }
    #endif

    // MARK: - 按「全部」或「单款耳机」动态查询统计

    private func filteredSamples(forDevice deviceName: String?) -> [AudioExposureSample] {
        guard let deviceName else { return samples }
        return samples.filter { $0.deviceName == deviceName }
    }

    func overview(forDevice deviceName: String?) -> UsageOverviewSummary {
        buildOverview(from: filteredSamples(forDevice: deviceName))
    }

    func personalRecords(forDevice deviceName: String?) -> PersonalUsageRecords {
        buildPersonalRecords(from: filteredSamples(forDevice: deviceName))
    }

    func snapshot(for range: StatsTimeRange, offset: Int, deviceName: String?, isEnglish: Bool = false) -> PeriodUsageSnapshot {
        let source = filteredSamples(forDevice: deviceName)
        let calendar = Calendar.current
        let now = Date()

        switch range {
        case .week:
            let currentEnd = calendar.date(byAdding: .day, value: offset * 7, to: calendar.startOfDay(for: now)) ?? now
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: currentEnd) ?? now
            let start = calendar.date(byAdding: .day, value: -6, to: currentEnd) ?? currentEnd
            let prevStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start

            let periodSamples = source.filter { $0.startDate >= start && $0.startDate < endExclusive }
            let prevSamples = source.filter { $0.startDate >= prevStart && $0.startDate < start }

            let totalMins = TimeIntervalMerger.mergedMinutes(for: periodSamples)
            let prevMins = TimeIntervalMerger.mergedMinutes(for: prevSamples)

            let fmt = DateFormatter(); fmt.dateFormat = "M.d"
            let dayFmt = DateFormatter()
            dayFmt.locale = Locale(identifier: isEnglish ? "en_US" : "zh_CN")
            dayFmt.dateFormat = isEnglish ? "EEE" : "E"

            let points: [UsageChartPoint] = (0..<7).map { i in
                let d = calendar.date(byAdding: .day, value: i, to: start) ?? start
                let list = periodSamples.filter { calendar.isDate($0.startDate, inSameDayAs: d) }
                return UsageChartPoint(label: dayFmt.string(from: d), minutes: TimeIntervalMerger.mergedMinutes(for: list))
            }

            return PeriodUsageSnapshot(
                range: .week,
                title: "\(fmt.string(from: start)) — \(fmt.string(from: currentEnd))",
                totalMinutes: totalMins,
                deltaMinutes: prevMins > 0 ? totalMins - prevMins : nil,
                chartPoints: points
            )

        case .month:
            let target = calendar.date(byAdding: .month, value: offset, to: now) ?? now
            let comps = calendar.dateComponents([.year, .month], from: target)
            let start = calendar.date(from: comps) ?? target
            let endExclusive = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let prevStart = calendar.date(byAdding: .month, value: -1, to: start) ?? start

            let periodSamples = source.filter { $0.startDate >= start && $0.startDate < endExclusive }
            let prevSamples = source.filter { $0.startDate >= prevStart && $0.startDate < start }

            let totalMins = TimeIntervalMerger.mergedMinutes(for: periodSamples)
            let prevMins = TimeIntervalMerger.mergedMinutes(for: prevSamples)

            let monthTitleFmt = DateFormatter()
            monthTitleFmt.locale = Locale(identifier: isEnglish ? "en_US" : "zh_CN")
            monthTitleFmt.dateFormat = isEnglish ? "MMM yyyy" : "yyyy.MM"

            let points: [UsageChartPoint] = (0..<4).map { idx in
                let wStart = calendar.date(byAdding: .day, value: idx * 7, to: start) ?? start
                let wEnd = idx == 3 ? endExclusive : (calendar.date(byAdding: .day, value: (idx + 1) * 7, to: start) ?? endExclusive)
                let list = periodSamples.filter { $0.startDate >= wStart && $0.startDate < wEnd }
                return UsageChartPoint(label: isEnglish ? "W\(idx + 1)" : "第\(idx + 1)周", minutes: TimeIntervalMerger.mergedMinutes(for: list))
            }

            return PeriodUsageSnapshot(
                range: .month,
                title: monthTitleFmt.string(from: start),
                totalMinutes: totalMins,
                deltaMinutes: prevMins > 0 ? totalMins - prevMins : nil,
                chartPoints: points
            )

        case .year:
            let target = calendar.date(byAdding: .year, value: offset, to: now) ?? now
            let year = calendar.component(.year, from: target)
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? target
            let endExclusive = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? start
            let prevStart = calendar.date(from: DateComponents(year: year - 1, month: 1, day: 1)) ?? start

            let periodSamples = source.filter { $0.startDate >= start && $0.startDate < endExclusive }
            let prevSamples = source.filter { $0.startDate >= prevStart && $0.startDate < start }

            let totalMins = TimeIntervalMerger.mergedMinutes(for: periodSamples)
            let prevMins = TimeIntervalMerger.mergedMinutes(for: prevSamples)

            let points: [UsageChartPoint] = (1...12).map { m in
                let mStart = calendar.date(from: DateComponents(year: year, month: m, day: 1)) ?? start
                let mEnd = calendar.date(byAdding: .month, value: 1, to: mStart) ?? mStart
                let list = periodSamples.filter { $0.startDate >= mStart && $0.startDate < mEnd }
                return UsageChartPoint(label: isEnglish ? "\(m)" : "\(m)月", minutes: TimeIntervalMerger.mergedMinutes(for: list))
            }

            return PeriodUsageSnapshot(
                range: .year,
                title: "\(year)",
                totalMinutes: totalMins,
                deltaMinutes: prevMins > 0 ? totalMins - prevMins : nil,
                chartPoints: points
            )

        case .all:
            let totalMins = TimeIntervalMerger.mergedMinutes(for: source)
            let byMonth = Dictionary(grouping: source) { s -> Date in
                let c = calendar.dateComponents([.year, .month], from: s.startDate)
                return calendar.date(from: c) ?? s.startDate
            }
            let recentMonths = byMonth.keys.sorted().suffix(6)
            let mFmt = DateFormatter()
            mFmt.locale = Locale(identifier: isEnglish ? "en_US" : "zh_CN")
            mFmt.dateFormat = isEnglish ? "MMM" : "M月"
            let points = recentMonths.map { d in
                UsageChartPoint(label: mFmt.string(from: d), minutes: TimeIntervalMerger.mergedMinutes(for: byMonth[d] ?? []))
            }

            return PeriodUsageSnapshot(
                range: .all,
                title: isEnglish ? "All Time" : "全部",
                totalMinutes: totalMins,
                deltaMinutes: nil,
                chartPoints: points
            )
        }
    }

    // MARK: - 持久化与内部计算

    private func applyAndPersist(_ newSamples: [AudioExposureSample], source: String) {
        let sorted = newSamples.sorted { $0.startDate > $1.startDate }
        samples = sorted
        dataSourceLabel = source
        defaults.set(source, forKey: sourceLabelKey)
        deviceSummaries = buildDeviceSummaries(from: sorted)
        saveCache(sorted)
    }

    private func loadCachedSamples() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let decoded = try? JSONDecoder().decode([AudioExposureSample].self, from: data),
              !decoded.isEmpty else {
            return
        }
        samples = decoded
        deviceSummaries = buildDeviceSummaries(from: decoded)
    }

    private func saveCache(_ list: [AudioExposureSample]) {
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }

    private func buildOverview(from input: [AudioExposureSample]) -> UsageOverviewSummary {
        guard !input.isEmpty else { return .empty }
        let calendar = Calendar.current
        let totalMins = TimeIntervalMerger.mergedMinutes(for: input)
        let first = input.map(\.startDate).min()
        let last = input.map(\.endDate).max()

        let spanDays: Int
        if let f = first, let l = last {
            spanDays = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: f), to: calendar.startOfDay(for: l)).day ?? 0) + 1)
        } else {
            spanDays = 1
        }
        let activeDays = Set(input.map { calendar.startOfDay(for: $0.startDate) }).count
        let coverage = min(100.0, (Double(activeDays) / Double(spanDays)) * 100.0)
        let dailyAvg = totalMins / Double(max(1, activeDays))

        return UsageOverviewSummary(
            rawSampleCount: input.count,
            firstDate: first,
            lastDate: last,
            spanDays: spanDays,
            activeDays: activeDays,
            activeCoveragePercent: coverage,
            totalMinutes: totalMins,
            dailyAverageMinutes: dailyAvg,
            weightedAverageDecibels: Self.weightedAverageDecibels(for: input)
        )
    }

    private func buildDeviceSummaries(from input: [AudioExposureSample]) -> [HeadphoneUsageSummary] {
        guard !input.isEmpty else { return [] }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: input, by: \.deviceName)
        let raw = grouped.map { name, group in
            (name: name, mins: TimeIntervalMerger.mergedMinutes(for: group), group: group)
        }
        let grandTotal = max(1.0, raw.reduce(0.0) { $0 + $1.mins })

        return raw.map { item in
            let days = Set(item.group.map { calendar.startOfDay(for: $0.startDate) }).count
            return HeadphoneUsageSummary(
                id: item.name,
                deviceName: item.name,
                category: item.group.first?.category ?? HeadphoneCategory.infer(from: item.name),
                totalMinutes: item.mins,
                sharePercentage: (item.mins / grandTotal) * 100.0,
                averageDecibels: Self.weightedAverageDecibels(for: item.group),
                activeDays: days,
                lastUsedDate: item.group.map(\.endDate).max() ?? Date()
            )
        }
        .sorted { $0.totalMinutes > $1.totalMinutes }
    }

    private func buildPersonalRecords(from input: [AudioExposureSample]) -> PersonalUsageRecords {
        guard !input.isEmpty else { return .empty }
        let calendar = Calendar.current

        let byDay = Dictionary(grouping: input) { calendar.startOfDay(for: $0.startDate) }
        var longestDayMins = 0.0
        var longestDayDate: Date?
        for (day, list) in byDay {
            let m = TimeIntervalMerger.mergedMinutes(for: list)
            if m > longestDayMins {
                longestDayMins = m
                longestDayDate = day
            }
        }

        let sessions = TimeIntervalMerger.merge(samples: input, gapToleranceSeconds: 15 * 60)
        let bestSession = sessions.max { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }
        let longestSessionMins = bestSession.map { $0.end.timeIntervalSince($0.start) / 60.0 } ?? 0

        let sortedDays = byDay.keys.sorted()
        var bestStreak = 0, curStreak = 0
        var bestStart: Date?, bestEnd: Date?, curStart: Date?, prevDay: Date?
        for day in sortedDays {
            if let prev = prevDay,
               let next = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(day, inSameDayAs: next) {
                curStreak += 1
            } else {
                curStreak = 1
                curStart = day
            }
            if curStreak > bestStreak {
                bestStreak = curStreak
                bestStart = curStart
                bestEnd = day
            }
            prevDay = day
        }

        let byMonth = Dictionary(grouping: input) { s -> Date in
            let c = calendar.dateComponents([.year, .month], from: s.startDate)
            return calendar.date(from: c) ?? s.startDate
        }
        var longestMonthMins = 0.0
        var longestMonthDate: Date?
        for (mDate, list) in byMonth {
            let m = TimeIntervalMerger.mergedMinutes(for: list)
            if m > longestMonthMins {
                longestMonthMins = m
                longestMonthDate = mDate
            }
        }

        return PersonalUsageRecords(
            longestDayMinutes: longestDayMins,
            longestDayDate: longestDayDate,
            longestSessionMinutes: longestSessionMins,
            longestSessionStart: bestSession?.start,
            longestSessionEnd: bestSession?.end,
            longestStreakDays: bestStreak,
            longestStreakStart: bestStart,
            longestStreakEnd: bestEnd,
            longestMonthMinutes: longestMonthMins,
            longestMonthDate: longestMonthDate
        )
    }

    private static func weightedAverageDecibels(for list: [AudioExposureSample]) -> Double {
        guard !list.isEmpty else { return 0 }
        let weighted = list.reduce(0.0) { $0 + $1.decibels * $1.durationMinutes }
        let total = list.reduce(0.0) { $0 + $1.durationMinutes }
        return total > 0 ? weighted / total : 0
    }
}

// MARK: - Apple 健康 export.xml 流式解析器
private final class HealthExportXMLParser: NSObject, XMLParserDelegate {
    private var results: [AudioExposureSample] = []
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()

    static func parse(fileURL: URL) throws -> [AudioExposureSample] {
        guard let parser = XMLParser(contentsOf: fileURL) else {
            throw NSError(domain: "HealthExportXML", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read XML"])
        }
        let delegate = HealthExportXMLParser()
        parser.delegate = delegate
        parser.parse()
        return delegate.results
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard elementName == "Record",
              attributeDict["type"] == "HKQuantityTypeIdentifierHeadphoneAudioExposure",
              let startStr = attributeDict["startDate"],
              let endStr = attributeDict["endDate"],
              let valueStr = attributeDict["value"],
              let db = Double(valueStr),
              let startDate = dateFormatter.date(from: startStr),
              let endDate = dateFormatter.date(from: endStr) else {
            return
        }

        let deviceName = Self.extractDeviceName(
            deviceAttr: attributeDict["device"],
            sourceName: attributeDict["sourceName"]
        )

        results.append(
            AudioExposureSample(
                id: UUID(),
                startDate: startDate,
                endDate: endDate,
                decibels: db,
                deviceName: deviceName,
                category: HeadphoneCategory.infer(from: deviceName)
            )
        )
    }

    private static func extractDeviceName(deviceAttr: String?, sourceName: String?) -> String {
        if let raw = deviceAttr, let range = raw.range(of: "name:") {
            let tail = raw[range.upperBound...]
            let endIdx = tail.firstIndex(of: ",") ?? tail.firstIndex(of: ">") ?? tail.endIndex
            let extracted = tail[..<endIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            if !extracted.isEmpty {
                return extracted
            }
        }
        if let src = sourceName, !src.isEmpty {
            return src
        }
        return "Headphones"
    }
}
