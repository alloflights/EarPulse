import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case zh = "zh"
    case en = "en"

    var id: String { rawValue }
}

/// 轻量中英双语管理
@MainActor
final class LanguageStore: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        }
    }

    private let storageKey = "earphone_useage_language"

    var isEnglish: Bool { language == .en }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "earphone_useage_language"),
           let parsed = AppLanguage(rawValue: saved) {
            self.language = parsed
        } else {
            let preferred = Locale.preferredLanguages.first ?? "zh"
            self.language = preferred.lowercased().hasPrefix("zh") ? .zh : .en
        }
    }

    func toggle() {
        language = (language == .zh) ? .en : .zh
    }

    var statsTab: String { isEnglish ? "Stats" : "统计" }
    var devicesTab: String { isEnglish ? "Devices" : "设备" }

    var appleHealth: String { isEnglish ? "Apple Health" : "Apple 健康" }
    var importXML: String { isEnglish ? "Import export.xml" : "导入 export.xml" }
    var syncHealth: String { isEnglish ? "Sync Health" : "同步健康" }

    var last7Days: String { isEnglish ? "Last 7 Days" : "过去一周" }
    var yesterday: String { isEnglish ? "Yesterday" : "昨天" }
    var avgLabel: String { isEnglish ? "Avg" : "平均" }
    var hourlyTitle: String { isEnglish ? "Hourly" : "逐小时使用" }
    var todayAvgNoise: String { isEnglish ? "Today Noise" : "今日平均噪音" }
    var weekAvgNoise: String { isEnglish ? "7-Day Noise" : "本周平均噪音" }

    var bestDay: String { isEnglish ? "Best Day" : "单日最长" }
    var longestSession: String { isEnglish ? "Longest" : "单次最长" }
    var streak: String { isEnglish ? "Streak" : "连续记录" }
    var bestMonth: String { isEnglish ? "Best Month" : "单月最长" }

    var connected: String { isEnglish ? "Connected" : "已连接" }
    var notConnected: String { isEnglish ? "Disconnected" : "未连接" }
    var primaryDevice: String { isEnglish ? "Primary" : "主力耳机" }
    var manageDevices: String { isEnglish ? "Manage" : "排序与合并" }
    var mergeAction: String { isEnglish ? "Merge" : "合并数据" }
    var unmergeAll: String { isEnglish ? "Reset" : "恢复默认" }
    var doneLabel: String { isEnglish ? "Done" : "完成" }

    var limitsTitle: String { isEnglish ? "Limits" : "限额提醒" }
    var dailyLimit: String { isEnglish ? "Daily" : "每日限额" }
    var sessionLimit: String { isEnglish ? "Session" : "单次限额" }
    var limitReached: String { isEnglish ? "Reached" : "已达限额" }

    func categoryTitle(_ category: HeadphoneCategory) -> String {
        switch category {
        case .airPodsPro: return "AirPods Pro"
        case .airPodsMax: return "AirPods Max"
        case .airPods: return "AirPods"
        case .beoplayEX: return "Beoplay EX"
        case .beoplayH95: return "Beoplay H95"
        case .sonyOverEar: return "Sony WH"
        case .sonyInEar: return "Sony WF"
        case .boseOverEar: return "Bose QC Ultra"
        case .boseInEar: return "Bose QC Earbuds"
        case .sennheiserOverEar: return "Sennheiser Momentum"
        case .beatsOverEar: return "Beats Studio Pro"
        case .beatsInEar: return "Beats Fit Pro"
        case .marshallOverEar: return "Marshall Major"
        case .overEar: return isEnglish ? "Over-Ear" : "头戴式"
        case .inEar: return isEnglish ? "In-Ear" : "入耳式"
        }
    }

    func daysCount(_ count: Int) -> String {
        isEnglish ? "\(count)d" : "\(count) 天"
    }

    func dailyAvg(hours: Int, mins: Int) -> String {
        isEnglish ? "\(hours)h \(mins)m /d" : "日均 \(hours)h \(mins)m"
    }
}
