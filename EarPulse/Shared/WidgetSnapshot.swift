import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 主 App 与桌面小组件共享的今日耳机使用频率与分贝快照
struct EarWidgetSnapshot: Codable, Sendable {
    static let defaultAppGroupID = "group.com.earpulse.hearinghealth"
    static let storageKey = "earuseage_widget_snapshot_v1"
    static let fileName = "earuseage_widget_snapshot_v1.json"

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

    /// 自动探测当前证书签名后实际生效的 App Group（兼容证书重签修改 Bundle ID / App Group ID）
    static func resolvedAppGroupID() -> String? {
        var candidates: [String] = []

        if let bid = Bundle.main.bundleIdentifier {
            // 如果当前是小组件扩展（如 xxx.widget），还原主 App Bundle ID
            let baseID = bid.hasSuffix(".widget") ? String(bid.dropLast(".widget".count)) : bid
            candidates.append("group.\(baseID)")
        }
        candidates.append(defaultAppGroupID)

        // 尝试从 embedded.mobileprovision 中提取证书实际授予的 App Group
        if let provisionGroup = extractAppGroupFromMobileProvision() {
            candidates.insert(provisionGroup, at: 0)
        }

        for gid in candidates {
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: gid) != nil {
                return gid
            }
        }
        return nil
    }

    private static func extractAppGroupFromMobileProvision() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .isoLatin1),
              let startRange = raw.range(of: "<?xml"),
              let endRange = raw.range(of: "</plist>") else {
            return nil
        }
        let plistStr = String(raw[startRange.lowerBound..<endRange.upperBound])
        guard let plistData = plistStr.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else {
            return nil
        }
        return groups.first
    }

    func saveToSharedStore() {
        guard let data = try? JSONEncoder().encode(self) else { return }

        if let gid = Self.resolvedAppGroupID() {
            if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: gid) {
                let fileURL = dir.appendingPathComponent(Self.fileName)
                try? data.write(to: fileURL, options: .atomic)
            }
            if let defaults = UserDefaults(suiteName: gid) {
                defaults.set(data, forKey: Self.storageKey)
                defaults.synchronize()
            }
        } else {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }

        #if canImport(WidgetKit) && os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func loadFromSharedStore() -> EarWidgetSnapshot? {
        let decoder = JSONDecoder()

        if let gid = resolvedAppGroupID() {
            if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: gid) {
                let fileURL = dir.appendingPathComponent(fileName)
                if let data = try? Data(contentsOf: fileURL),
                   let decoded = try? decoder.decode(EarWidgetSnapshot.self, from: data) {
                    return decoded
                }
            }
            if let defaults = UserDefaults(suiteName: gid),
               let data = defaults.data(forKey: storageKey),
               let decoded = try? decoder.decode(EarWidgetSnapshot.self, from: data) {
                return decoded
            }
        }

        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? decoder.decode(EarWidgetSnapshot.self, from: data) {
            return decoded
        }
        return nil
    }
}
