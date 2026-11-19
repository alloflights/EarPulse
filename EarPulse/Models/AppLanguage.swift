import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case zh = "zh"
    case en = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

/// 轻量中英双语状态管理（默认跟随系统语言，支持 App 内一键切换并持久化）
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

    // MARK: - 极简双语文案（无任何说明性废话）

    var statsTab: String { isEnglish ? "Stats" : "统计" }
    var devicesTab: String { isEnglish ? "Devices" : "设备" }

    var allScope: String { isEnglish ? "All" : "全部" }
    var totalUsage: String { isEnglish ? "Total" : "累计佩戴" }
    var appleHealth: String { isEnglish ? "Apple Health" : "Apple 健康" }
    var importXML: String { isEnglish ? "Import export.xml" : "导入 export.xml" }
    var syncHealth: String { isEnglish ? "Sync Health" : "同步健康" }

    var bestDay: String { isEnglish ? "Best Day" : "单日最长" }
    var longestSession: String { isEnglish ? "Longest" : "单次最长" }
    var streak: String { isEnglish ? "Streak" : "连续记录" }
    var bestMonth: String { isEnglish ? "Best Month" : "单月最长" }

    var connected: String { isEnglish ? "Connected" : "已连接" }
    var notConnected: String { isEnglish ? "Disconnected" : "未连接" }
    var byDevice: String { isEnglish ? "Devices" : "每款耳机" }

    func rangeTitle(_ range: StatsTimeRange) -> String {
        switch range {
        case .week: return isEnglish ? "W" : "周"
        case .month: return isEnglish ? "M" : "月"
        case .year: return isEnglish ? "Y" : "年"
        case .all: return isEnglish ? "All" : "总共"
        }
    }

    func categoryTitle(_ category: HeadphoneCategory) -> String {
        switch category {
        case .airPodsPro: return "AirPods Pro"
        case .airPodsMax: return "AirPods Max"
        case .airPods: return "AirPods"
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
