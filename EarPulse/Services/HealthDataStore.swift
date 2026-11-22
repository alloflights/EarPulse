import Combine
import Foundation
#if os(iOS)
import HealthKit
#endif

/// 100% 真实数据引擎：支持 HealthKit 静默同步、export.xml 永久缓存、设备自定义排序、多设备数据合并与屏幕时间风逐小时分析
@MainActor
final class HealthDataStore: ObservableObject {
    @Published var samples: [AudioExposureSample] = []
    @Published var deviceSummaries: [HeadphoneUsageSummary] = []

    /// 用户自定义排序（按设备名）
    @Published var customDeviceOrder: [String] = []
    /// 用户设备合并映射（源设备名 -> 目标设备名）
    @Published var deviceMergeMap: [String: String] = [:]

    @Published var isLoading: Bool = false
    @Published var dataSourceLabel: String = ""
    @Published var errorMessage: String?

    #if os(iOS)
    private let healthStore = HKHealthStore()
    #endif
    private let defaults = UserDefaults.standard
    private let hkConnectedKey = "earphone_useage_hk_connected"
    private let sourceLabelKey = "earphone_useage_source_label"
    private let customOrderKey = "earphone_useage_custom_order"
    private let mergeMapKey = "earphone_useage_merge_map"

    private var cacheFileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("earphone_useage_real_cache.json")
    }

    var hasRealData: Bool {
        !samples.isEmpty
    }

    var primaryDevice: HeadphoneUsageSummary? {
        deviceSummaries.first(where: \.isPrimary) ?? deviceSummaries.first
    }

    init() {
        customDeviceOrder = defaults.stringArray(forKey: customOrderKey) ?? []
        deviceMergeMap = (defaults.dictionary(forKey: mergeMapKey) as? [String: String]) ?? [:]
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

    // MARK: - 设备排序与多设备数据合并

    /// 解析合并后的规范设备名
    func canonicalName(for rawName: String) -> String {
        var current = rawName
        var visited = Set<String>()
        while let mapped = deviceMergeMap[current], !visited.contains(mapped) {
            visited.insert(current)
            current = mapped
        }
        return current
    }

    /// 将多个源耳机合并到目标耳机
    func mergeDevice(_ sourceName: String, into targetName: String) {
        guard sourceName != targetName else { return }
        let resolvedTarget = canonicalName(for: targetName)
        deviceMergeMap[sourceName] = resolvedTarget
        // 同步更新已指向 sourceName 的映射，防止链式环
        for (k, v) in deviceMergeMap where v == sourceName {
            deviceMergeMap[k] = resolvedTarget
        }
        defaults.set(deviceMergeMap, forKey: mergeMapKey)
        customDeviceOrder.removeAll { $0 == sourceName }
        defaults.set(customDeviceOrder, forKey: customOrderKey)
        rebuildSummaries()
    }

    /// 移动耳机排列顺序
    func moveDevice(fromIndex: Int, toIndex: Int) {
        var names = deviceSummaries.map(\.deviceName)
        guard names.indices.contains(fromIndex), names.indices.contains(toIndex), fromIndex != toIndex else { return }
        let item = names.remove(at: fromIndex)
        names.insert(item, at: toIndex)
        customDeviceOrder = names
        defaults.set(customDeviceOrder, forKey: customOrderKey)
        rebuildSummaries()
    }

    /// 恢复默认排序并取消所有合并
    func resetCustomizations() {
        deviceMergeMap = [:]
        customDeviceOrder = []
        defaults.removeObject(forKey: mergeMapKey)
        defaults.removeObject(forKey: customOrderKey)
        rebuildSummaries()
    }

    // MARK: - HealthKit & export.xml

    func connectAppleHealth() async {
        errorMessage = nil
        #if os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "HealthKit unavailable"
            return
        }
        guard let exposureType = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [exposureType])
            defaults.set(true, forKey: hkConnectedKey)
            await fetchFromHealthKit(silent: false)
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
        #else
        errorMessage = "iOS HealthKit only"
        #endif
    }

    #if os(iOS)
    func fetchFromHealthKit(silent: Bool) async {
        guard HKHealthStore.isHealthDataAvailable(),
              let exposureType = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure) else { return }

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
                if !silent { Haptics.success() }
            } else if !silent && samples.isEmpty {
                errorMessage = "No records found"
                Haptics.error()
            }
        } catch {
            if !silent {
                errorMessage = error.localizedDescription
                Haptics.error()
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
                errorMessage = "No headphone records in XML"
                Haptics.error()
            } else {
                applyAndPersist(parsed, source: "export.xml")
                errorMessage = nil
                Haptics.success()
            }
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    // MARK: - 屏幕时间风格统计（过去一周 + 昨天/指定日 24 小时逐小时分耳机）

    func screenTimeSnapshot(selectedDate: Date?, isEnglish: Bool) -> ScreenTimeStatsSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let activeDay = calendar.startOfDay(for: selectedDate ?? yesterday)

        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: isEnglish ? "en_US" : "zh_CN")
        dayFmt.dateFormat = isEnglish ? "EEE" : "E"

        // 过去 7 天（含今天，默认高亮昨天）
        let weekBars: [DailyUsageBar] = (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let daySamples = samples.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            return DailyUsageBar(
                id: day,
                date: day,
                weekdayLabel: dayFmt.string(from: day),
                totalMinutes: TimeIntervalMerger.mergedMinutes(for: daySamples),
                isYesterday: calendar.isDate(day, inSameDayAs: yesterday)
            )
        }

        let nonZeroDays = weekBars.filter { $0.totalMinutes > 0 }
        let weekAvg = nonZeroDays.isEmpty
            ? 0
            : nonZeroDays.reduce(0.0) { $0 + $1.totalMinutes } / Double(nonZeroDays.count)

        // 选中日 24 小时逐小时按合并后耳机名拆解
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: activeDay) ?? activeDay
        let daySamples = samples.filter { $0.endDate > activeDay && $0.startDate < dayEnd }
        let selectedDayTotal = TimeIntervalMerger.mergedMinutes(for: daySamples)

        // 按设备累计时长排序分配稳定色标
        var deviceDayMinutes: [String: Double] = [:]
        var hourlyMap: [Int: [String: Double]] = [:]

        for sample in daySamples {
            let devName = canonicalName(for: sample.deviceName)
            let clampedStart = max(sample.startDate, activeDay)
            let clampedEnd = min(sample.endDate, dayEnd)
            guard clampedEnd > clampedStart else { continue }

            // 将跨小时样本切分到每个具体小时槽 (0...23)，防夏令时/边界死循环
            var cursor = clampedStart
            while cursor < clampedEnd {
                let hour = calendar.component(.hour, from: cursor)
                let hourFloor = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
                let nextHourStart = calendar.date(byAdding: .hour, value: 1, to: hourFloor) ?? dayEnd
                let segEnd = min(clampedEnd, nextHourStart)
                guard segEnd > cursor else { break }
                let mins = segEnd.timeIntervalSince(cursor) / 60.0
                if mins > 0 {
                    hourlyMap[hour, default: [:]][devName, default: 0] += mins
                    deviceDayMinutes[devName, default: 0] += mins
                }
                cursor = segEnd
            }
        }

        let sortedDayDevices = deviceDayMinutes.sorted { $0.value > $1.value }
        let breakdowns: [DayDeviceBreakdown] = sortedDayDevices.enumerated().map { idx, entry in
            DayDeviceBreakdown(id: entry.key, deviceName: entry.key, minutes: entry.value, colorIndex: idx)
        }

        var hourlyBars: [HourlyDeviceUsageBar] = []
        for hour in 0..<24 {
            guard let devDict = hourlyMap[hour] else { continue }
            // 归一化防止单小时超过 60 分钟
            let rawSum = devDict.values.reduce(0, +)
            let scale = rawSum > 60 ? (60.0 / rawSum) : 1.0
            for item in breakdowns {
                if let mins = devDict[item.deviceName], mins > 0.2 {
                    hourlyBars.append(
                        HourlyDeviceUsageBar(
                            id: "\(hour)-\(item.deviceName)",
                            hour: hour,
                            deviceName: item.deviceName,
                            minutes: mins * scale
                        )
                    )
                }
            }
        }

        return ScreenTimeStatsSnapshot(
            weekBars: weekBars,
            weekAverageMinutes: weekAvg,
            selectedDate: activeDay,
            selectedDayTotalMinutes: selectedDayTotal,
            hourlyBars: hourlyBars,
            dayBreakdowns: breakdowns
        )
    }

    // MARK: - 单款耳机详情统计（供设备页点击弹窗使用）

    private func filteredSamples(forDevice deviceName: String?) -> [AudioExposureSample] {
        guard let deviceName else { return samples }
        return samples.filter { canonicalName(for: $0.deviceName) == deviceName }
    }

    func overview(forDevice deviceName: String?) -> UsageOverviewSummary {
        buildOverview(from: filteredSamples(forDevice: deviceName))
    }

    func personalRecords(forDevice deviceName: String?) -> PersonalUsageRecords {
        buildPersonalRecords(from: filteredSamples(forDevice: deviceName))
    }

    // MARK: - 持久化与聚合

    private func applyAndPersist(_ newSamples: [AudioExposureSample], source: String) {
        let sorted = newSamples.sorted { $0.startDate > $1.startDate }
        samples = sorted
        dataSourceLabel = source
        defaults.set(source, forKey: sourceLabelKey)
        rebuildSummaries()
        saveCache(sorted)
    }

    private func loadCachedSamples() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let decoded = try? JSONDecoder().decode([AudioExposureSample].self, from: data),
              !decoded.isEmpty else { return }
        samples = decoded
        rebuildSummaries()
    }

    private func saveCache(_ list: [AudioExposureSample]) {
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }

    private func rebuildSummaries() {
        guard !samples.isEmpty else {
            deviceSummaries = []
            return
        }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: samples) { canonicalName(for: $0.deviceName) }
        let raw = grouped.map { name, group in
            (name: name, mins: TimeIntervalMerger.mergedMinutes(for: group), group: group)
        }
        let grandTotal = max(1.0, raw.reduce(0.0) { $0 + $1.mins })
        let primaryName = raw.max { $0.mins < $1.mins }?.name

        var summaries = raw.map { item -> HeadphoneUsageSummary in
            let days = Set(item.group.map { calendar.startOfDay(for: $0.startDate) }).count
            return HeadphoneUsageSummary(
                id: item.name,
                deviceName: item.name,
                category: HeadphoneCategory.infer(from: item.name),
                totalMinutes: item.mins,
                sharePercentage: (item.mins / grandTotal) * 100.0,
                averageDecibels: Self.weightedAverageDecibels(for: item.group),
                activeDays: days,
                lastUsedDate: item.group.map(\.endDate).max() ?? Date(),
                isPrimary: item.name == primaryName
            )
        }

        // 按用户自定义排序（未排序的按累计时长降序追加）
        summaries.sort { lhs, rhs in
            let li = customDeviceOrder.firstIndex(of: lhs.deviceName)
            let ri = customDeviceOrder.firstIndex(of: rhs.deviceName)
            switch (li, ri) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.totalMinutes > rhs.totalMinutes
            }
        }
        deviceSummaries = summaries
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

    #if os(macOS)
    /// 仅限 Mac 本机预览使用的内存数据（通过 #if os(macOS) 隔离，绝不编入 iOS .ipa）
    func loadMacPreviewOnlyData() {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        var list: [AudioExposureSample] = []

        let specs: [(name: String, cat: HeadphoneCategory, db: Double)] = [
            ("AirPods Pro", .airPodsPro, 62.5),
            ("Beoplay EX", .beoplayEX, 66.0),
            ("AirPods Max", .airPodsMax, 59.5),
            ("Sony WH-1000XM5", .sonyOverEar, 65.0)
        ]

        for dayOffset in 0..<45 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart) else { continue }
            let slots: [(hour: Int, dur: Double, devIdx: Int)] = [
                (1, 52, 0),
                (8, 44, 0),
                (10, 38, 1),
                (14, 58, (dayOffset % 2 == 0) ? 2 : 0),
                (17, 46, 1),
                (21, 55, (dayOffset % 3 == 0) ? 3 : 0),
                (23, 48, 0)
            ]
            for slot in slots {
                if (dayOffset + slot.hour) % 5 == 0 && dayOffset > 1 { continue }
                if let s = calendar.date(byAdding: .hour, value: slot.hour, to: day), s < now {
                    let e = min(now, s.addingTimeInterval(slot.dur * 60))
                    if e > s {
                        let d = specs[slot.devIdx]
                        list.append(AudioExposureSample(id: UUID(), startDate: s, endDate: e, decibels: d.db, deviceName: d.name, category: d.cat))
                    }
                }
            }
        }

        samples = list.sorted { $0.startDate > $1.startDate }
        rebuildSummaries()
    }
    #endif
}

// MARK: - Apple 健康 export.xml 解析器
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
              let endDate = dateFormatter.date(from: endStr) else { return }

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
            if !extracted.isEmpty { return extracted }
        }
        if let src = sourceName, !src.isEmpty { return src }
        return "Headphones"
    }
}
