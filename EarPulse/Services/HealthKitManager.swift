import Combine
import Foundation
import HealthKit
import SwiftUI

/// 负责接入 Apple HealthKit 读取历史耳机分贝数据、按时间区间去重统计、计算个人纪录与多耳机使用时间分析
@MainActor
final class HealthKitManager: ObservableObject {
    @Published var isHealthDataAvailable: Bool = HKHealthStore.isHealthDataAvailable()
    @Published var isAuthorized: Bool = false
    @Published var isUsingDemoData: Bool = true
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = "演示历史数据（近 180 天）"

    @Published var samples: [AudioExposureSample] = []
    @Published var deviceSummaries: [HeadphoneUsageSummary] = []
    @Published var dailyPoints: [DailyExposurePoint] = []
    @Published var loudEvents: [LoudExposureEvent] = []
    @Published var personalRecords: PersonalUsageRecords = .empty
    @Published var usageAnalysis: UsageTimeAnalysis = .empty

    private let healthStore = HKHealthStore()

    init() {
        loadDemoData()
    }

    // MARK: - 首页当日衍生指标

    var todaySamples: [AudioExposureSample] {
        let calendar = Calendar.current
        return samples.filter { calendar.isDateInToday($0.startDate) }
    }

    var todayAverageDecibels: Double {
        let target = todaySamples.isEmpty ? Array(samples.prefix(20)) : todaySamples
        return Self.weightedAverageDecibels(for: target)
    }

    var todayPeakDecibels: Double {
        let target = todaySamples.isEmpty ? Array(samples.prefix(20)) : todaySamples
        return target.map(\.decibels).max() ?? 0
    }

    var todayTotalMinutes: Double {
        TimeIntervalMerger.mergedMinutes(for: todaySamples)
    }

    var todayDosePercentage: Double {
        AcousticDoseCalculator.dosePercentage(for: todaySamples)
    }

    var remainingSafeQuotaPercentage: Double {
        max(0.0, 100.0 - todayDosePercentage)
    }

    var mostUsedDevice: HeadphoneUsageSummary? {
        deviceSummaries.first
    }

    /// 多耳机对比洞察文案
    var multiDeviceInsight: String {
        guard deviceSummaries.count >= 2 else {
            return "连接更多耳机后，这里会自动为你对比不同耳机的使用时间与护耳表现。"
        }
        let sortedByDb = deviceSummaries.sorted { $0.averageDecibels < $1.averageDecibels }
        guard let safest = sortedByDb.first, let loudest = sortedByDb.last else { return "" }
        let diff = Int(round(loudest.averageDecibels - safest.averageDecibels))
        if diff >= 5 {
            return "使用「\(safest.deviceName)」时的平均音量比「\(loudest.deviceName)」低约 \(diff) dB，降噪或封闭隔音能明显减少你在嘈杂环境不自觉调大音量的习惯。"
        } else {
            return "你在不同耳机间的聆听音量保持得比较稳定，差距仅约 \(diff) dB，继续保持良好的听觉保护习惯。"
        }
    }

    /// 本周听觉健康报告
    var weeklyReport: WeeklyHearingReport {
        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())) ?? Date()
        let weekSamples = samples.filter { $0.startDate >= weekStart }
        let avgDb = Self.weightedAverageDecibels(for: weekSamples)
        let totalHours = TimeIntervalMerger.mergedMinutes(for: weekSamples) / 60.0
        let safeDays = dailyPoints.filter { $0.averageDecibels > 0 && $0.averageDecibels < 80 }.count
        let weekDevices = buildDeviceSummaries(from: weekSamples)
        let topDevice = weekDevices.first ?? deviceSummaries.first

        let (grade, title): (String, String)
        switch avgDb {
        case ..<68: (grade, title) = ("S", "极致护耳达人")
        case 68..<75: (grade, title) = ("A", "健康聆听模范")
        case 75..<82: (grade, title) = ("B", "轻度偏高 · 可优化")
        default: (grade, title) = ("C", "高音量预警 · 需护耳")
        }

        return WeeklyHearingReport(
            grade: grade,
            gradeTitle: title,
            averageDecibels: avgDb,
            totalHours: totalHours,
            safeDaysCount: safeDays,
            primaryDeviceName: topDevice?.deviceName ?? "暂无设备",
            primaryDeviceCategory: topDevice?.category ?? .airPodsPro,
            insightText: multiDeviceInsight
        )
    }

    // MARK: - 按 周 / 月 / 年 / 总共 聚合使用时间与每款耳机时长

    func snapshot(for range: StatsTimeRange, offset: Int) -> PeriodUsageSnapshot {
        let calendar = Calendar.current
        let now = Date()

        switch range {
        case .week:
            // 以最近 7 天为基准向前/向后翻周
            let currentEnd = calendar.date(byAdding: .day, value: offset * 7, to: calendar.startOfDay(for: now)) ?? now
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: currentEnd) ?? now
            let start = calendar.date(byAdding: .day, value: -6, to: currentEnd) ?? currentEnd
            let prevStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start

            let periodSamples = samples.filter { $0.startDate >= start && $0.startDate < endExclusive }
            let prevSamples = samples.filter { $0.startDate >= prevStart && $0.startDate < start }

            let totalMins = TimeIntervalMerger.mergedMinutes(for: periodSamples)
            let prevMins = TimeIntervalMerger.mergedMinutes(for: prevSamples)

            let formatter = DateFormatter()
            formatter.dateFormat = "M.d"
            let title = "\(formatter.string(from: start)) — \(formatter.string(from: currentEnd))"

            let dayFmt = DateFormatter()
            dayFmt.locale = Locale(identifier: "zh_CN")
            dayFmt.dateFormat = "E"
            let chartPoints: [UsageChartPoint] = (0..<7).map { idx in
                let d = calendar.date(byAdding: .day, value: idx, to: start) ?? start
                let daySamples = periodSamples.filter { calendar.isDate($0.startDate, inSameDayAs: d) }
                return UsageChartPoint(
                    label: dayFmt.string(from: d),
                    minutes: TimeIntervalMerger.mergedMinutes(for: daySamples),
                    averageDecibels: Self.weightedAverageDecibels(for: daySamples)
                )
            }

            return PeriodUsageSnapshot(
                range: .week,
                title: title,
                totalMinutes: totalMins,
                previousPeriodMinutes: prevMins,
                deltaMinutes: totalMins - prevMins,
                averageDecibels: Self.weightedAverageDecibels(for: periodSamples),
                deviceSummaries: buildDeviceSummaries(from: periodSamples),
                chartPoints: chartPoints
            )

        case .month:
            let targetMonthDate = calendar.date(byAdding: .month, value: offset, to: now) ?? now
            let comps = calendar.dateComponents([.year, .month], from: targetMonthDate)
            let start = calendar.date(from: comps) ?? targetMonthDate
            let endExclusive = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let prevStart = calendar.date(byAdding: .month, value: -1, to: start) ?? start

            let periodSamples = samples.filter { $0.startDate >= start && $0.startDate < endExclusive }
            let prevSamples = samples.filter { $0.startDate >= prevStart && $0.startDate < start }

            let totalMins = TimeIntervalMerger.mergedMinutes(for: periodSamples)
            let prevMins = TimeIntervalMerger.mergedMinutes(for: prevSamples)

            let title = "\(comps.year ?? 2026) 年 \(comps.month ?? 1) 月"

            // 按 4-5 周分段出图
            let chartPoints: [UsageChartPoint] = (0..<4).map { weekIdx in
                let wStart = calendar.date(byAdding: .day, value: weekIdx * 7, to: start) ?? start
                let wEnd = weekIdx == 3 ? endExclusive : (calendar.date(byAdding: .day, value: (weekIdx + 1) * 7, to: start) ?? endExclusive)
                let wSamples = periodSamples.filter { $0.startDate >= wStart && $0.startDate < wEnd }
                return UsageChartPoint(
                    label: "第\(weekIdx + 1)周",
                    minutes: TimeIntervalMerger.mergedMinutes(for: wSamples),
                    averageDecibels: Self.weightedAverageDecibels(for: wSamples)
                )
            }

            return PeriodUsageSnapshot(
                range: .month,
                title: title,
                totalMinutes: totalMins,
                previousPeriodMinutes: prevMins,
                deltaMinutes: totalMins - prevMins,
                averageDecibels: Self.weightedAverageDecibels(for: periodSamples),
                deviceSummaries: buildDeviceSummaries(from: periodSamples),
                chartPoints: chartPoints
            )

        case .year:
            let targetYearDate = calendar.date(byAdding: .year, value: offset, to: now) ?? now
            let year = calendar.component(.year, from: targetYearDate)
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? targetYearDate
            let endExclusive = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? start
            let prevStart = calendar.date(from: DateComponents(year: year - 1, month: 1, day: 1)) ?? start

            let periodSamples = samples.filter { $0.startDate >= start && $0.startDate < endExclusive }
            let prevSamples = samples.filter { $0.startDate >= prevStart && $0.startDate < start }

            let totalMins = TimeIntervalMerger.mergedMinutes(for: periodSamples)
            let prevMins = TimeIntervalMerger.mergedMinutes(for: prevSamples)

            let chartPoints: [UsageChartPoint] = (1...12).map { month in
                let mStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? start
                let mEnd = calendar.date(byAdding: .month, value: 1, to: mStart) ?? mStart
                let mSamples = periodSamples.filter { $0.startDate >= mStart && $0.startDate < mEnd }
                return UsageChartPoint(
                    label: "\(month)月",
                    minutes: TimeIntervalMerger.mergedMinutes(for: mSamples),
                    averageDecibels: Self.weightedAverageDecibels(for: mSamples)
                )
            }

            return PeriodUsageSnapshot(
                range: .year,
                title: "\(year) 年",
                totalMinutes: totalMins,
                previousPeriodMinutes: prevMins > 0 ? prevMins : nil,
                deltaMinutes: prevMins > 0 ? totalMins - prevMins : nil,
                averageDecibels: Self.weightedAverageDecibels(for: periodSamples),
                deviceSummaries: buildDeviceSummaries(from: periodSamples),
                chartPoints: chartPoints
            )

        case .all:
            let totalMins = TimeIntervalMerger.mergedMinutes(for: samples)
            let groupedByMonth = Dictionary(grouping: samples) { sample -> Date in
                let c = calendar.dateComponents([.year, .month], from: sample.startDate)
                return calendar.date(from: c) ?? sample.startDate
            }
            let sortedMonths = groupedByMonth.keys.sorted().suffix(6)
            let monthFmt = DateFormatter()
            monthFmt.dateFormat = "M月"
            let chartPoints = sortedMonths.map { monthDate in
                let list = groupedByMonth[monthDate] ?? []
                return UsageChartPoint(
                    label: monthFmt.string(from: monthDate),
                    minutes: TimeIntervalMerger.mergedMinutes(for: list),
                    averageDecibels: Self.weightedAverageDecibels(for: list)
                )
            }

            return PeriodUsageSnapshot(
                range: .all,
                title: "已读取全部历史",
                totalMinutes: totalMins,
                previousPeriodMinutes: nil,
                deltaMinutes: nil,
                averageDecibels: Self.weightedAverageDecibels(for: samples),
                deviceSummaries: deviceSummaries,
                chartPoints: chartPoints
            )
        }
    }

    // MARK: - HealthKit 授权与全历史数据读取

    func requestHealthKitAuthorizationAndFetch() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "当前设备不支持 HealthKit，已保留演示数据"
            isUsingDemoData = true
            return
        }

        guard let exposureType = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure),
              let eventType = HKCategoryType.categoryType(forIdentifier: .headphoneAudioExposureEvent) else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [exposureType, eventType])
            isAuthorized = true
            await fetchRealHealthKitData()
        } catch {
            statusMessage = "HealthKit 授权失败：\(error.localizedDescription)"
            isUsingDemoData = true
        }
    }

    func fetchRealHealthKitData() async {
        guard let exposureType = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure),
              let eventType = HKCategoryType.categoryType(forIdentifier: .headphoneAudioExposureEvent) else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        // 读取最近 2 年的全部耳机分贝历史，用于精确计算个人纪录与各款累计使用时间
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .year, value: -2, to: endDate) ?? endDate
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        do {
            let quantitySamples = try await queryQuantitySamples(type: exposureType, predicate: predicate)
            let categorySamples = try await queryCategorySamples(type: eventType, predicate: predicate)

            let unit = HKUnit.decibelAWeightedSoundPressureLevel()
            let mappedSamples: [AudioExposureSample] = quantitySamples.map { sample in
                let db = sample.quantity.doubleValue(for: unit)
                let resolvedName = Self.resolveDeviceName(from: sample)
                let category = HeadphoneCategory.infer(from: resolvedName)
                return AudioExposureSample(
                    id: sample.uuid,
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    decibels: db,
                    deviceName: resolvedName,
                    category: category
                )
            }

            let mappedEvents: [LoudExposureEvent] = categorySamples.map { event in
                let levelQty = event.metadata?[HKMetadataKeyAudioExposureLevel] as? HKQuantity
                let db = levelQty?.doubleValue(for: unit) ?? 85.0
                let durationQty = event.metadata?[HKMetadataKeyAudioExposureDuration] as? HKQuantity
                let mins = (durationQty?.doubleValue(for: .minute())) ?? max(1, event.endDate.timeIntervalSince(event.startDate) / 60.0)
                return LoudExposureEvent(date: event.startDate, decibels: db, durationMinutes: mins)
            }

            if mappedSamples.isEmpty {
                statusMessage = "健康 App 暂无耳机分贝记录（已切换演示数据预览）"
                loadDemoData()
            } else {
                isUsingDemoData = false
                statusMessage = "已同步 Apple 健康 \(mappedSamples.count) 条历史记录"
                loudEvents = mappedEvents
                applySamples(mappedSamples)
            }
        } catch {
            statusMessage = "读取健康数据失败：\(error.localizedDescription)"
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
                let samples = (results as? [HKQuantitySample]) ?? []
                continuation.resume(returning: samples)
            }
            healthStore.execute(query)
        }
    }

    private func queryCategorySamples(type: HKCategoryType, predicate: NSPredicate) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 100, sortDescriptors: [sort]) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let samples = (results as? [HKCategorySample]) ?? []
                continuation.resume(returning: samples)
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
        let sourceName = sample.sourceRevision.source.name
        if !sourceName.isEmpty {
            return "\(sourceName) 耳机音频"
        }
        return "未知耳机设备"
    }

    // MARK: - 聚合、个人纪录与使用时间分析引擎

    func switchToDemoMode() {
        isUsingDemoData = true
        statusMessage = "演示历史数据（近 180 天）"
        loadDemoData()
    }

    private func applySamples(_ newSamples: [AudioExposureSample]) {
        samples = newSamples
        deviceSummaries = buildDeviceSummaries(from: newSamples)
        dailyPoints = buildDailyPoints(from: newSamples)
        personalRecords = buildPersonalRecords(from: newSamples)
        usageAnalysis = buildUsageTimeAnalysis(from: newSamples)
    }

    private static func weightedAverageDecibels(for list: [AudioExposureSample]) -> Double {
        guard !list.isEmpty else { return 0 }
        let weighted = list.reduce(0.0) { $0 + $1.decibels * $1.durationMinutes }
        let total = list.reduce(0.0) { $0 + $1.durationMinutes }
        return total > 0 ? weighted / total : 0
    }

    private func buildDeviceSummaries(from input: [AudioExposureSample]) -> [HeadphoneUsageSummary] {
        guard !input.isEmpty else { return [] }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: input, by: \.deviceName)

        let rawTotals: [(name: String, mins: Double, group: [AudioExposureSample])] = grouped.map { name, group in
            (name, TimeIntervalMerger.mergedMinutes(for: group), group)
        }
        let grandTotal = max(1.0, rawTotals.reduce(0.0) { $0 + $1.mins })

        return rawTotals.map { item in
            let group = item.group
            let avgDb = Self.weightedAverageDecibels(for: group)
            let peakDb = group.map(\.decibels).max() ?? 0
            let loudMins = TimeIntervalMerger.mergedMinutes(for: group.filter { $0.decibels >= 80 })
            let lastUsed = group.map(\.endDate).max() ?? Date()
            let category = group.first?.category ?? HeadphoneCategory.infer(from: item.name)
            let uniqueDays = Set(group.map { calendar.startOfDay(for: $0.startDate) }).count
            let sessions = TimeIntervalMerger.merge(samples: group, gapToleranceSeconds: 15 * 60)
            let longestSession = sessions.map { $0.end.timeIntervalSince($0.start) / 60.0 }.max() ?? 0

            return HeadphoneUsageSummary(
                id: item.name,
                deviceName: item.name,
                category: category,
                totalMinutes: item.mins,
                sharePercentage: (item.mins / grandTotal) * 100.0,
                averageDecibels: avgDb,
                peakDecibels: peakDb,
                activeDays: uniqueDays,
                longestSessionMinutes: longestSession,
                sampleCount: group.count,
                lastUsedDate: lastUsed,
                highVolumeMinutes: loudMins
            )
        }
        .sorted { $0.totalMinutes > $1.totalMinutes }
    }

    private func buildPersonalRecords(from input: [AudioExposureSample]) -> PersonalUsageRecords {
        guard !input.isEmpty else { return .empty }
        let calendar = Calendar.current

        // 1. 单日佩戴最长（按天去重合并）
        let byDay = Dictionary(grouping: input) { calendar.startOfDay(for: $0.startDate) }
        var longestDayMinutes = 0.0
        var longestDayDate: Date?
        for (day, list) in byDay {
            let mins = TimeIntervalMerger.mergedMinutes(for: list)
            if mins > longestDayMinutes {
                longestDayMinutes = mins
                longestDayDate = day
            }
        }

        // 2. 单次佩戴最长（15 分钟内连续区间合并）
        let sessions = TimeIntervalMerger.merge(samples: input, gapToleranceSeconds: 15 * 60)
        let bestSession = sessions.max { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }
        let longestSessionMinutes = bestSession.map { $0.end.timeIntervalSince($0.start) / 60.0 } ?? 0

        // 3. 连续记录最长（连续活跃天数）
        let sortedDays = byDay.keys.sorted()
        var bestStreak = 0
        var bestStreakStart: Date?
        var bestStreakEnd: Date?
        var currentStreak = 0
        var currentStart: Date?
        var previousDay: Date?

        for day in sortedDays {
            if let prev = previousDay,
               let expectedNext = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(day, inSameDayAs: expectedNext) {
                currentStreak += 1
            } else {
                currentStreak = 1
                currentStart = day
            }
            if currentStreak > bestStreak {
                bestStreak = currentStreak
                bestStreakStart = currentStart
                bestStreakEnd = day
            }
            previousDay = day
        }

        // 4. 单月佩戴最长
        let byMonth = Dictionary(grouping: input) { sample -> Date in
            let comps = calendar.dateComponents([.year, .month], from: sample.startDate)
            return calendar.date(from: comps) ?? sample.startDate
        }
        var longestMonthMinutes = 0.0
        var longestMonthDate: Date?
        for (monthDate, list) in byMonth {
            let mins = TimeIntervalMerger.mergedMinutes(for: list)
            if mins > longestMonthMinutes {
                longestMonthMinutes = mins
                longestMonthDate = monthDate
            }
        }

        return PersonalUsageRecords(
            longestDayMinutes: longestDayMinutes,
            longestDayDate: longestDayDate,
            longestSessionMinutes: longestSessionMinutes,
            longestSessionStart: bestSession?.start,
            longestSessionEnd: bestSession?.end,
            longestStreakDays: bestStreak,
            longestStreakStart: bestStreakStart,
            longestStreakEnd: bestStreakEnd,
            longestMonthMinutes: longestMonthMinutes,
            longestMonthDate: longestMonthDate
        )
    }

    private func buildUsageTimeAnalysis(from input: [AudioExposureSample]) -> UsageTimeAnalysis {
        guard !input.isEmpty else { return .empty }
        let calendar = Calendar.current

        let mergedTotalMins = TimeIntervalMerger.mergedMinutes(for: input)
        let firstDate = input.map(\.startDate).min()
        let lastDate = input.map(\.endDate).max()

        let spanDays: Int
        if let f = firstDate, let l = lastDate {
            let startDay = calendar.startOfDay(for: f)
            let endDay = calendar.startOfDay(for: l)
            spanDays = max(1, (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1)
        } else {
            spanDays = 1
        }

        let activeDays = Set(input.map { calendar.startOfDay(for: $0.startDate) }).count
        let coverage = min(100.0, (Double(activeDays) / Double(spanDays)) * 100.0)
        let dailyAverage = mergedTotalMins / Double(max(1, activeDays))
        let weightedAvgDb = Self.weightedAverageDecibels(for: input)

        // 24 小时四大时段统计
        var nightMins = 0.0     // 00:00 - 06:00
        var morningMins = 0.0   // 06:00 - 12:00
        var afternoonMins = 0.0 // 12:00 - 18:00
        var eveningMins = 0.0   // 18:00 - 24:00

        for sample in input {
            let hour = calendar.component(.hour, from: sample.startDate)
            switch hour {
            case 0..<6: nightMins += sample.durationMinutes
            case 6..<12: morningMins += sample.durationMinutes
            case 12..<18: afternoonMins += sample.durationMinutes
            default: eveningMins += sample.durationMinutes
            }
        }

        let bucketTotal = max(1.0, nightMins + morningMins + afternoonMins + eveningMins)
        let buckets: [TimeOfDayBucket] = [
            TimeOfDayBucket(id: "night", title: "深夜伴眠", timeRangeText: "00:00 – 06:00", icon: "moon.stars.fill", minutes: nightMins, share: nightMins / bucketTotal, color: .indigo),
            TimeOfDayBucket(id: "morning", title: "上午通勤", timeRangeText: "06:00 – 12:00", icon: "sunrise.fill", minutes: morningMins, share: morningMins / bucketTotal, color: .orange),
            TimeOfDayBucket(id: "afternoon", title: "午后专注", timeRangeText: "12:00 – 18:00", icon: "sun.max.fill", minutes: afternoonMins, share: afternoonMins / bucketTotal, color: .teal),
            TimeOfDayBucket(id: "evening", title: "夜间放松", timeRangeText: "18:00 – 24:00", icon: "sparkles", minutes: eveningMins, share: eveningMins / bucketTotal, color: Color(red: 0.56, green: 0.72, blue: 0.98))
        ]

        let topBucket = buckets.max { $0.minutes < $1.minutes }
        let totalHoursInt = Int(round(mergedTotalMins / 60.0))
        let tailPhrase: String
        let habitSummary: String
        switch topBucket?.id {
        case "night":
            tailPhrase = "几乎每天都戴着入睡"
            habitSummary = "你在 00:00 – 06:00 时段的使用占比最高（\(Int(round((topBucket?.share ?? 0) * 100)))%），属于典型的「深夜伴眠型」听众。建议在睡前开启定时停止播放，避免整夜佩戴压迫耳道。"
        case "evening":
            tailPhrase = "夜晚是你最离不开耳机的时刻"
            habitSummary = "你的佩戴高峰集中在 18:00 – 24:00（占比 \(Int(round((topBucket?.share ?? 0) * 100)))%），夜间独处或放松听歌居多，音量整体控制得较为温和。"
        case "morning":
            tailPhrase = "每个清晨都有音乐陪你出发"
            habitSummary = "上午 06:00 – 12:00 是你的高频使用时段（占比 \(Int(round((topBucket?.share ?? 0) * 100)))%），通勤途中建议开启主动降噪以降低环境底噪带来的音量抬升。"
        default:
            tailPhrase = "耳机的陪伴贯穿你的白昼"
            habitSummary = "午后 12:00 – 18:00 是你佩戴最集中的时段（占比 \(Int(round((topBucket?.share ?? 0) * 100)))%），专注学习或办公时建议配合 60-60 护耳计时定时摘机休息。"
        }

        let headline = "\(spanDays) 天佩戴耳机 \(totalHoursInt) 小时，\(tailPhrase)"

        return UsageTimeAnalysis(
            headline: headline,
            rawSampleCount: input.count,
            firstDate: firstDate,
            lastDate: lastDate,
            spanDays: spanDays,
            activeDays: activeDays,
            activeCoveragePercent: coverage,
            mergedTotalMinutes: mergedTotalMins,
            dailyAverageMinutes: dailyAverage,
            weightedAverageDecibels: weightedAvgDb,
            timeOfDayBuckets: buckets,
            habitSummary: habitSummary
        )
    }

    private func buildDailyPoints(from input: [AudioExposureSample]) -> [DailyExposurePoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let daySamples = input.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            return DailyExposurePoint(
                date: day,
                averageDecibels: Self.weightedAverageDecibels(for: daySamples),
                peakDecibels: daySamples.map(\.decibels).max() ?? 0,
                totalMinutes: TimeIntervalMerger.mergedMinutes(for: daySamples)
            )
        }
    }

    /// 生成近 180 天、多耳机真实感历史演示数据（涵盖通勤、午后专注、夜间放松与深夜伴眠）
    func loadDemoData() {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        var generated: [AudioExposureSample] = []

        struct DemoDeviceSpec {
            let name: String
            let category: HeadphoneCategory
            let baseDb: Double
        }

        let devices: [DemoDeviceSpec] = [
            DemoDeviceSpec(name: "AirPods Pro (第 2 代)", category: .airPodsPro, baseDb: 63.5),
            DemoDeviceSpec(name: "AirPods Max 银色", category: .airPodsMax, baseDb: 60.5),
            DemoDeviceSpec(name: "AirPods 2", category: .airPods, baseDb: 74.5),
            DemoDeviceSpec(name: "Sony WH-1000XM5", category: .overEar, baseDb: 66.0),
            DemoDeviceSpec(name: "EarPods (USB-C)", category: .wired, baseDb: 71.5)
        ]

        // 180 天历史：保留 5 天间隙以体现真实连续记录（例如连续 42 天）
        for dayOffset in 0..<180 {
            if dayOffset == 43 || dayOffset == 95 || dayOffset == 141 { continue }
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart) else { continue }

            // 1. 深夜伴眠段（00:30 - 02:55，偶尔更长，形成单次最长记录）
            if dayOffset % 5 != 4 {
                let sleepDuration: Double = (dayOffset == 27) ? 268 : Double(88 + (dayOffset * 13) % 72)
                if let start = calendar.date(byAdding: .minute, value: 30 + (dayOffset % 20), to: day),
                   start < now {
                    let end = min(now, start.addingTimeInterval(sleepDuration * 60))
                    if end > start {
                        let spec = devices[0]
                        generated.append(AudioExposureSample(
                            id: UUID(),
                            startDate: start,
                            endDate: end,
                            decibels: spec.baseDb - 4.5 + sin(Double(dayOffset)) * 3.0,
                            deviceName: spec.name,
                            category: spec.category
                        ))
                    }
                }
            }

            // 2. 上午通勤段（08:15）
            if let start = calendar.date(byAdding: .minute, value: 8 * 60 + 15, to: day), start < now {
                let dur: Double = (dayOffset == 14) ? 145 : Double(36 + (dayOffset * 7) % 34)
                let end = min(now, start.addingTimeInterval(dur * 60))
                if end > start {
                    let spec = (dayOffset % 3 == 0) ? devices[2] : devices[0]
                    generated.append(AudioExposureSample(
                        id: UUID(),
                        startDate: start,
                        endDate: end,
                        decibels: spec.baseDb + 3.0 + cos(Double(dayOffset)) * 4.0,
                        deviceName: spec.name,
                        category: spec.category
                    ))
                }
            }

            // 3. 午后学习/办公段（14:10）
            if dayOffset % 2 == 0 || dayOffset == 14 {
                if let start = calendar.date(byAdding: .minute, value: 14 * 60 + 10, to: day), start < now {
                    let dur: Double = (dayOffset == 14) ? 210 : Double(58 + (dayOffset * 11) % 66)
                    let end = min(now, start.addingTimeInterval(dur * 60))
                    if end > start {
                        let spec = (dayOffset % 4 == 0) ? devices[1] : devices[3]
                        generated.append(AudioExposureSample(
                            id: UUID(),
                            startDate: start,
                            endDate: end,
                            decibels: spec.baseDb + sin(Double(dayOffset * 3)) * 3.5,
                            deviceName: spec.name,
                            category: spec.category
                        ))
                    }
                }
            }

            // 4. 夜晚放松段（20:40）
            if dayOffset % 3 != 2 || dayOffset == 14 {
                if let start = calendar.date(byAdding: .minute, value: 20 * 60 + 40, to: day), start < now {
                    let dur: Double = (dayOffset == 14) ? 180 : Double(42 + (dayOffset * 17) % 55)
                    let end = min(now, start.addingTimeInterval(dur * 60))
                    if end > start {
                        let spec = (dayOffset % 5 == 0) ? devices[4] : ((dayOffset % 2 == 0) ? devices[1] : devices[0])
                        generated.append(AudioExposureSample(
                            id: UUID(),
                            startDate: start,
                            endDate: end,
                            decibels: spec.baseDb + 1.5 + cos(Double(dayOffset * 2)) * 4.5,
                            deviceName: spec.name,
                            category: spec.category
                        ))
                    }
                }
            }
        }

        loudEvents = [
            LoudExposureEvent(
                date: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
                decibels: 86.4,
                durationMinutes: 32
            ),
            LoudExposureEvent(
                date: calendar.date(byAdding: .day, value: -11, to: now) ?? now,
                decibels: 84.1,
                durationMinutes: 25
            )
        ]

        applySamples(generated.sorted { $0.startDate > $1.startDate })
    }
}
