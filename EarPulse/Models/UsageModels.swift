import Foundation
import SwiftUI

/// 耳机形态与主流真实产品图资源映射
enum HeadphoneCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case airPodsPro = "AirPods Pro"
    case airPodsMax = "AirPods Max"
    case airPods = "AirPods"
    case beoplayEX = "Beoplay EX"
    case beoplayH95 = "Beoplay H95"
    case sonyOverEar = "Sony WH"
    case sonyInEar = "Sony WF"
    case boseOverEar = "Bose QC Ultra"
    case boseInEar = "Bose QC Earbuds"
    case sennheiserOverEar = "Sennheiser Momentum"
    case beatsOverEar = "Beats Studio Pro"
    case beatsInEar = "Beats Fit Pro"
    case marshallOverEar = "Marshall Major"
    case overEar = "头戴式"
    case inEar = "入耳式"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .airPodsPro: return "airpodspro"
        case .airPodsMax: return "airpodsmax"
        case .airPods: return "airpods"
        case .beoplayEX, .sonyInEar, .boseInEar, .beatsInEar, .inEar: return "earbuds"
        case .beoplayH95, .sonyOverEar, .boseOverEar, .sennheiserOverEar, .beatsOverEar, .marshallOverEar, .overEar:
            return "headphones"
        }
    }

    /// Assets.xcassets 中对应的真实产品图资源名
    var localAssetName: String? {
        switch self {
        case .airPodsPro: return "apple_airpods_pro"
        case .airPodsMax: return "apple_airpods_max"
        case .airPods: return "apple_airpods"
        case .beoplayEX: return "beoplay_ex"
        case .beoplayH95: return "beoplay_h95"
        case .sonyOverEar: return "sony_xm5"
        case .sonyInEar: return "sony_wf_xm5"
        case .boseOverEar: return "bose_qc_ultra"
        case .boseInEar: return "bose_qc_ultra_earbuds"
        case .sennheiserOverEar: return "sennheiser_m4"
        case .beatsOverEar: return "beats_studio_pro"
        case .beatsInEar: return "beats_fit_pro"
        case .marshallOverEar: return "marshall_major"
        case .overEar, .inEar: return nil
        }
    }

    /// Resources/LaunchAnimations 中对应的苹果原版透明开盖动画文件名（不含扩展名）
    var launchAnimationName: String? {
        switch self {
        case .airPodsPro: return "airpods_pro_open"
        case .airPodsMax: return "airpods_max_open"
        case .airPods: return "airpods_open"
        default: return nil
        }
    }

    static func infer(from deviceName: String, isWired: Bool = false) -> HeadphoneCategory {
        let lower = deviceName.lowercased()
        if lower.contains("airpod") && lower.contains("max") { return .airPodsMax }
        if lower.contains("airpod") && lower.contains("pro") { return .airPodsPro }
        if lower.contains("airpod") { return .airPods }

        if lower.contains("beoplay") || lower.contains("b&o") || lower.contains("bang") {
            if lower.contains("h95") || lower.contains("h100") || lower.contains("hx") || lower.contains("h9") || lower.contains("portal") {
                return .beoplayH95
            }
            return .beoplayEX
        }

        if lower.contains("wf-1000") || lower.contains("wf1000") || (lower.contains("sony") && (lower.contains("bud") || lower.contains("wf"))) {
            return .sonyInEar
        }
        if lower.contains("sony") || lower.contains("wh-1000") || lower.contains("xm5") || lower.contains("xm4") {
            return .sonyOverEar
        }

        if lower.contains("bose") || lower.contains("quietcomfort") || lower.contains("qc ultra") || lower.contains("qc45") {
            if lower.contains("earbud") || lower.contains("bud") || lower.contains("open") {
                return .boseInEar
            }
            return .boseOverEar
        }

        if lower.contains("sennheiser") || lower.contains("momentum") {
            return .sennheiserOverEar
        }

        if lower.contains("beats") {
            if lower.contains("fit") || lower.contains("bud") || lower.contains("powerbeats") {
                return .beatsInEar
            }
            return .beatsOverEar
        }

        if lower.contains("marshall") || lower.contains("major") || lower.contains("monitor") {
            return .marshallOverEar
        }

        if lower.contains("max") || lower.contains("headphone") || lower.contains("studio") ||
            lower.contains("solo") || lower.contains("头戴") {
            return .overEar
        }
        return .inEar
    }
}

/// 真实耳机分贝样本
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

/// 每款耳机的真实使用时间汇总
struct HeadphoneUsageSummary: Identifiable, Hashable, Sendable {
    let id: String
    let deviceName: String
    let category: HeadphoneCategory
    let totalMinutes: Double
    let sharePercentage: Double
    let averageDecibels: Double
    let activeDays: Int
    let lastUsedDate: Date
    let isPrimary: Bool

    var formattedDuration: String {
        DurationFormatter.hoursMinutes(minutes: totalMinutes)
    }
}

/// 屏幕时间风格：过去一周每天柱状点
struct DailyUsageBar: Identifiable, Sendable {
    let id: Date
    let date: Date
    let weekdayLabel: String
    let totalMinutes: Double
    let isYesterday: Bool
}

/// 屏幕时间风格：单日 24 小时逐小时按耳机堆叠柱状点
struct HourlyDeviceUsageBar: Identifiable, Sendable {
    let id: String
    let hour: Int
    let deviceName: String
    let minutes: Double
}

/// 单日耳机图例汇总
struct DayDeviceBreakdown: Identifiable, Sendable {
    let id: String
    let deviceName: String
    let minutes: Double
    let colorIndex: Int
}

/// 屏幕时间风格统计快照（过去一周 + 选中日 24 小时逐小时）
struct ScreenTimeStatsSnapshot: Sendable {
    let weekBars: [DailyUsageBar]
    let weekAverageMinutes: Double
    let selectedDate: Date
    let selectedDayTotalMinutes: Double
    let hourlyBars: [HourlyDeviceUsageBar]
    let dayBreakdowns: [DayDeviceBreakdown]
}

/// 个人纪录 4 项
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

/// 总体 / 单款使用时间摘要
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
