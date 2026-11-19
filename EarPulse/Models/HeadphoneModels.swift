import Foundation
import SwiftUI

/// 支持区分的耳机形态与贴图类型
enum HeadphoneCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case airPodsPro = "AirPods Pro"
    case airPodsMax = "AirPods Max"
    case airPods = "AirPods"
    case overEar = "头戴式耳机"
    case wired = "有线耳机"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .airPodsPro: return "入耳式主动降噪"
        case .airPodsMax: return "头戴式空间音频"
        case .airPods: return "半入耳式无线"
        case .overEar: return "蓝牙头戴式"
        case .wired: return "有线监听/直连"
        }
    }

    var sfSymbol: String {
        switch self {
        case .airPodsPro: return "airpodspro"
        case .airPodsMax: return "airpodsmax"
        case .airPods: return "airpods"
        case .overEar: return "headphones"
        case .wired: return "earbuds"
        }
    }

    var accentColor: Color {
        switch self {
        case .airPodsPro: return Color(red: 0.56, green: 0.72, blue: 0.98)
        case .airPodsMax: return .indigo
        case .airPods: return .teal
        case .overEar: return .purple
        case .wired: return .orange
        }
    }

    /// 根据系统/HealthKit 返回的设备名称自动匹配耳机形态
    static func infer(from deviceName: String, isWired: Bool = false) -> HeadphoneCategory {
        let lower = deviceName.lowercased()
        if lower.contains("max") {
            return .airPodsMax
        }
        if lower.contains("pro") && (lower.contains("airpod") || lower.contains("pod")) {
            return .airPodsPro
        }
        if lower.contains("airpod") {
            return .airPods
        }
        if isWired || lower.contains("earpod") || lower.contains("wired") || lower.contains("有线") {
            return .wired
        }
        if lower.contains("sony") || lower.contains("bose") || lower.contains("beats studio") ||
            lower.contains("sennheiser") || lower.contains("头戴") || lower.contains("xm") || lower.contains("qc") {
            return .overEar
        }
        return .airPodsPro
    }
}

/// 分贝安全等级（参考 Apple 听力健康与 WHO 声压标准）
enum ExposureLevel: String, Sendable {
    case safe = "柔和安全"
    case moderate = "适中良好"
    case caution = "偏高需留意"
    case loud = "过高易伤耳"

    static func from(decibels: Double) -> ExposureLevel {
        switch decibels {
        case ..<70: return .safe
        case 70..<80: return .moderate
        case 80..<90: return .caution
        default: return .loud
        }
    }

    var color: Color {
        switch self {
        case .safe: return .green
        case .moderate: return .teal
        case .caution: return .orange
        case .loud: return .pink
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .moderate: return "ear.badge.checkmark"
        case .caution: return "exclamationmark.triangle.fill"
        case .loud: return "waveform.badge.exclamationmark"
        }
    }

    var shortAdvice: String {
        switch self {
        case .safe: return "音量非常舒适，适合长时间轻松聆听。"
        case .moderate: return "处于日常安全范围，建议每小时休息 5 分钟。"
        case .caution: return "已接近 WHO 警戒线，建议开启降噪并调低 1-2 格音量。"
        case .loud: return "长期处于该分贝可能损伤听力，请立即降低音量。"
        }
    }
}

/// 统计时间范围维度（对应 周 / 月 / 年 / 总共）
enum StatsTimeRange: String, CaseIterable, Identifiable, Sendable {
    case week = "周"
    case month = "月"
    case year = "年"
    case all = "总共"

    var id: String { rawValue }
}

/// 单条耳机分贝样本记录
struct AudioExposureSample: Identifiable, Hashable, Sendable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let decibels: Double
    let deviceName: String
    let category: HeadphoneCategory

    var durationMinutes: Double {
        max(endDate.timeIntervalSince(startDate) / 60.0, 0.5)
    }

    var level: ExposureLevel {
        ExposureLevel.from(decibels: decibels)
    }
}

/// 按不同耳机聚合的使用时间与分贝统计
struct HeadphoneUsageSummary: Identifiable, Hashable, Sendable {
    let id: String
    let deviceName: String
    let category: HeadphoneCategory
    let totalMinutes: Double
    let sharePercentage: Double
    let averageDecibels: Double
    let peakDecibels: Double
    let activeDays: Int
    let longestSessionMinutes: Double
    let sampleCount: Int
    let lastUsedDate: Date
    let highVolumeMinutes: Double

    var level: ExposureLevel {
        ExposureLevel.from(decibels: averageDecibels)
    }

    /// 护耳评分 (0 - 100)
    var earHealthScore: Int {
        let dbPenalty = max(0, (averageDecibels - 65) * 1.9)
        let loudPenalty = min(25, (highVolumeMinutes / max(1, totalMinutes)) * 120)
        return max(35, min(100, Int(round(100 - dbPenalty - loudPenalty))))
    }

    var hoursPart: Int {
        Int(round(totalMinutes)) / 60
    }

    var minutesPart: Int {
        Int(round(totalMinutes)) % 60
    }

    var formattedDuration: String {
        DurationFormatter.hoursMinutes(minutes: totalMinutes)
    }
}

/// 个人纪录 4 项（单日最长 / 单次最长 / 连续天数最长 / 单月最长）
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

/// 24 小时佩戴时段分布项
struct TimeOfDayBucket: Identifiable, Sendable {
    let id: String
    let title: String
    let timeRangeText: String
    let icon: String
    let minutes: Double
    let share: Double
    let color: Color
}

/// 使用时间深度分析汇总（对应参考图杂志风总结 + 时段画像）
struct UsageTimeAnalysis: Sendable {
    let headline: String
    let rawSampleCount: Int
    let firstDate: Date?
    let lastDate: Date?
    let spanDays: Int
    let activeDays: Int
    let activeCoveragePercent: Double
    let mergedTotalMinutes: Double
    let dailyAverageMinutes: Double
    let weightedAverageDecibels: Double
    let timeOfDayBuckets: [TimeOfDayBucket]
    let habitSummary: String

    static let empty = UsageTimeAnalysis(
        headline: "连接耳机开始记录你的聆听足迹",
        rawSampleCount: 0,
        firstDate: nil,
        lastDate: nil,
        spanDays: 0,
        activeDays: 0,
        activeCoveragePercent: 0,
        mergedTotalMinutes: 0,
        dailyAverageMinutes: 0,
        weightedAverageDecibels: 0,
        timeOfDayBuckets: [],
        habitSummary: "暂无足够的历史记录进行时段分析。"
    )
}

/// 周期统计快照（用于 周 / 月 / 年 / 总共 视图）
struct PeriodUsageSnapshot: Sendable {
    let range: StatsTimeRange
    let title: String
    let totalMinutes: Double
    let previousPeriodMinutes: Double?
    let deltaMinutes: Double?
    let averageDecibels: Double
    let deviceSummaries: [HeadphoneUsageSummary]
    let chartPoints: [UsageChartPoint]
}

/// 图表柱状数据点
struct UsageChartPoint: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let minutes: Double
    let averageDecibels: Double
}

/// 每日分贝图表数据点（首页近 7 天用）
struct DailyExposurePoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let averageDecibels: Double
    let peakDecibels: Double
    let totalMinutes: Double

    var weekdayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}

/// 高音量系统警告事件
struct LoudExposureEvent: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let decibels: Double
    let durationMinutes: Double
}

/// 时间格式化辅助工具
enum DurationFormatter {
    static func hoursMinutes(minutes: Double) -> String {
        let total = max(0, Int(round(minutes)))
        let h = total / 60
        let m = total % 60
        if h > 0 {
            return "\(h)h \(m)min"
        }
        return "\(m)min"
    }

    static func splitHoursMinutes(minutes: Double) -> (hours: Int, mins: Int) {
        let total = max(0, Int(round(minutes)))
        return (total / 60, total % 60)
    }
}

/// 时间区间去重合并算法（复刻 HealthKit 原始样本防重叠统计）
enum TimeIntervalMerger {
    struct Span: Sendable {
        var start: Date
        var end: Date
    }

    /// 合并重叠时间区间，返回去重后的总时长（分钟）
    static func mergedMinutes(for samples: [AudioExposureSample]) -> Double {
        let merged = merge(samples: samples, gapToleranceSeconds: 0)
        return merged.reduce(0.0) { $0 + max(0, $1.end.timeIntervalSince($1.start)) / 60.0 }
    }

    /// 合并时间区间（支持指定间隔容差，例如 15 分钟内合并为同一次连续佩戴会话）
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

/// WHO 声剂量换算工具
enum AcousticDoseCalculator {
    /// 参考 WHO 3dB 交换率：80 dB 对应每周 40 小时（每日约 342 分钟）
    static func dailySafeMinutes(at decibels: Double) -> Double {
        guard decibels > 60 else { return 24 * 60 }
        let weeklyHoursAt80 = 40.0
        let weeklyHours = weeklyHoursAt80 / pow(2.0, (decibels - 80.0) / 3.0)
        return max(1.0, min(24.0 * 60.0, (weeklyHours / 7.0) * 60.0))
    }

    static func dosePercentage(for samples: [AudioExposureSample]) -> Double {
        let totalDose = samples.reduce(0.0) { partial, sample in
            guard sample.decibels >= 70 else {
                return partial + (sample.durationMinutes / (24 * 60)) * 8.0
            }
            let allowed = dailySafeMinutes(at: sample.decibels)
            return partial + (sample.durationMinutes / allowed) * 100.0
        }
        return min(150.0, max(0.0, totalDose))
    }

    static func formatSafeDuration(minutes: Double) -> String {
        if minutes >= 12 * 60 {
            return "12 小时以上"
        } else if minutes >= 60 {
            let h = Int(minutes) / 60
            let m = Int(minutes) % 60
            return m > 0 ? "\(h) 小时 \(m) 分钟" : "\(h) 小时"
        } else {
            return "\(max(1, Int(round(minutes)))) 分钟"
        }
    }
}

/// 本周听觉健康周报汇总模型
struct WeeklyHearingReport: Sendable {
    let grade: String
    let gradeTitle: String
    let averageDecibels: Double
    let totalHours: Double
    let safeDaysCount: Int
    let primaryDeviceName: String
    let primaryDeviceCategory: HeadphoneCategory
    let insightText: String
}
