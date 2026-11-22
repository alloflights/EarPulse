import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 主 App 与桌面小组件共享的今日耳机使用频率与分贝快照
struct EarWidgetSnapshot: Codable, Sendable {
    static let appGroupID = "group.com.earpulse.hearinghealth"
    static let storageKey = "earuseage_widget_snapshot_v1"

    let updatedAt: Date
    let todayTotalMinutes: Double
    let todayAverageDecibels: Double
    let weekAverageDecibels: Double
    let activeDeviceName: String
    /// 今日 0...23 共 24 小时的每小时佩戴分钟数（0...60）
    let hourlyMinutes: [Double]

    static let placeholder = EarWidgetSnapshot(
        updatedAt: Date(),
        todayTotalMinutes: 194,
        todayAverageDecibels: 63,
        weekAverageDecibels: 64,
        activeDeviceName: "AirPods Pro",
        hourlyMinutes: [
            0, 0, 0, 0, 0, 0,
            0, 12, 34, 22, 18, 8,
            0, 26, 42, 16, 0, 14,
            24, 38, 12, 0, 0, 0
        ]
    )

    static let empty = EarWidgetSnapshot(
        updatedAt: Date(),
        todayTotalMinutes: 0,
        todayAverageDecibels: 0,
        weekAverageDecibels: 0,
        activeDeviceName: "earuseage",
        hourlyMinutes: Array(repeating: 0, count: 24)
    )

    func saveToSharedStore() {
        let defaults = UserDefaults(suiteName: Self.appGroupID) ?? .standard
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
        #if canImport(WidgetKit) && os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func loadFromSharedStore() -> EarWidgetSnapshot? {
        let defaults = UserDefaults(suiteName: Self.appGroupID) ?? .standard
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(EarWidgetSnapshot.self, from: data) else {
            return nil
        }
        return decoded
    }
}
