import Foundation
import SwiftUI

/// 精简设备分类：Apple 官方 3 款 + 其他品牌仅区分「头戴式 / 入耳式」
enum HeadphoneCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case airPodsPro = "AirPods Pro"
    case airPodsMax = "AirPods Max"
    case airPods = "AirPods"
    case overEar = "头戴式"
    case inEar = "入耳式"

    var id: String { rawValue }

    var isAppleOfficial: Bool {
        switch self {
        case .airPodsPro, .airPodsMax, .airPods: return true
        case .overEar, .inEar: return false
        }
    }

    /// 苹果系统蓝牙原生 SF Symbol（纯透明无白边）
    var sfSymbol: String {
        switch self {
        case .airPodsPro: return "airpodspro"
        case .airPodsMax: return "airpodsmax"
        case .airPods: return "airpods"
        case .overEar: return "headphones"
        case .inEar: return "earbuds"
        }
    }

    /// 本地 Assets.xcassets 可选透明 PNG 产品图资源名
    var localAssetName: String? {
        switch self {
        case .airPodsPro: return "apple_airpods_pro"
        case .airPodsMax: return "apple_airpods_max"
        case .airPods: return "apple_airpods"
        case .overEar, .inEar: return nil
        }
    }

    /// 移除带白底的 JPEG 直链，确保在纯黑液态玻璃底上绝对无白边
    var officialAppleImageURL: URL? {
        nil
    }

    static func infer(from deviceName: String, isWired: Bool = false) -> HeadphoneCategory {
        let lower = deviceName.lowercased()
        if lower.contains("airpod") && lower.contains("max") { return .airPodsMax }
        if lower.contains("airpod") && lower.contains("pro") { return .airPodsPro }
        if lower.contains("airpod") { return .airPods }

        if lower.contains("max") || lower.contains("headphone") || lower.contains("studio") ||
            lower.contains("wh-") || lower.contains("xm") || lower.contains("qc") ||
            lower.contains("bose") || lower.contains("sennheiser") || lower.contains("solo") ||
            lower.contains("头戴") {
            return .overEar
        }
        return .inEar
    }
}

enum StatsTimeRange: String, CaseIterable, Identifiable, Sendable {
    case week = "周"
    case month = "月"
    case year = "年"
    case all = "总共"

    var id: String { rawValue }
}

struct AudioExposureSample: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let decibels: Double
    let deviceName: String
    let category: HeadphoneCategory

    var durationMinutes: Double {
        max(endDate.timeIntervalSince(startDate) / 60.0, 0.2)
    }
}

struct HeadphoneUsageSummary: Identifiable, Hashable, Sendable {
    let id: String
    let deviceName: String
    let category: HeadphoneCategory
    let totalMinutes: Double
    let sharePercentage: Double
    let averageDecibels: Double
    let activeDays: Int
    let lastUsedDate: Date

    var formattedDuration: String {
        DurationFormatter.hoursMinutes(minutes: totalMinutes)
    }
}

struct PersonalUsageRecords: Sendable {
    let longestDayMinutes: Double
    let longestDayDate: Date?

    let longestSessionMinutes: Double
    let longestSessionStart: Date?
    let longestSessionEnd: Date?

    let longestStreakDays: Int
    let longestStreakStart: Date?
    let longestStreakEnd: Date?

    let longestMonthMinutes: Double
    let longestMonthDate: Date?

    static let empty = PersonalUsageRecords(
        longestDayMinutes: 0, longestDayDate: nil,
        longestSessionMinutes: 0, longestSessionStart: nil, longestSessionEnd: nil,
        longestStreakDays: 0, longestStreakStart: nil, longestStreakEnd: nil,
        longestMonthMinutes: 0, longestMonthDate: nil
    )
}

struct UsageOverviewSummary: Sendable {
    let rawSampleCount: Int
    let firstDate: Date?
    let lastDate: Date?
    let spanDays: Int
    let activeDays: Int
    let activeCoveragePercent: Double
    let totalMinutes: Double
    let dailyAverageMinutes: Double
    let weightedAverageDecibels: Double

    static let empty = UsageOverviewSummary(
        rawSampleCount: 0,
        firstDate: nil,
        lastDate: nil,
        spanDays: 0,
        activeDays: 0,
        activeCoveragePercent: 0,
        totalMinutes: 0,
        dailyAverageMinutes: 0,
        weightedAverageDecibels: 0
    )
}

struct PeriodUsageSnapshot: Sendable {
    let range: StatsTimeRange
    let title: String
    let totalMinutes: Double
    let deltaMinutes: Double?
    let chartPoints: [UsageChartPoint]
}

struct UsageChartPoint: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let minutes: Double
}

enum DurationFormatter {
    static func hoursMinutes(minutes: Double) -> String {
        let total = max(0, Int(round(minutes)))
        let h = total / 60
        let m = total % 60
        return h > 0 ? "\(h)h \(m)min" : "\(m)min"
    }

    static func split(minutes: Double) -> (hours: Int, mins: Int) {
        let total = max(0, Int(round(minutes)))
        return (total / 60, total % 60)
    }
}

enum TimeIntervalMerger {
    struct Span: Sendable {
        var start: Date
        var end: Date
    }

    static func mergedMinutes(for samples: [AudioExposureSample]) -> Double {
        merge(samples: samples, gapToleranceSeconds: 0)
            .reduce(0.0) { $0 + max(0, $1.end.timeIntervalSince($1.start)) / 60.0 }
    }

    static func merge(samples: [AudioExposureSample], gapToleranceSeconds: TimeInterval) -> [Span] {
        guard !samples.isEmpty else { return [] }
        let sorted = samples
            .filter { $0.endDate > $0.startDate }
            .sorted { $0.startDate < $1.startDate }
        guard let first = sorted.first else { return [] }

        var result: [Span] = [Span(start: first.startDate, end: first.endDate)]
        for sample in sorted.dropFirst() {
            var last = result[result.count - 1]
            if sample.startDate <= last.end.addingTimeInterval(gapToleranceSeconds) {
                if sample.endDate > last.end {
                    last.end = sample.endDate
                    result[result.count - 1] = last
                }
            } else {
                result.append(Span(start: sample.startDate, end: sample.endDate))
            }
        }
        return result
    }
}
