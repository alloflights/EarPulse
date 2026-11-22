import Combine
import Foundation
import UserNotifications

/// 实时检测耳机佩戴时长，并在达到自定义「每日限额」或「单次限额」时触发本地通知与震动提醒
@MainActor
final class UsageLimitMonitor: ObservableObject {
    @Published var dailyLimitEnabled: Bool {
        didSet {
            defaults.set(dailyLimitEnabled, forKey: Keys.dailyEnabled)
            onSettingsChanged()
        }
    }
    @Published var dailyLimitMinutes: Int {
        didSet {
            defaults.set(dailyLimitMinutes, forKey: Keys.dailyMinutes)
            onSettingsChanged()
        }
    }

    @Published var sessionLimitEnabled: Bool {
        didSet {
            defaults.set(sessionLimitEnabled, forKey: Keys.sessionEnabled)
            onSettingsChanged()
        }
    }
    @Published var sessionLimitMinutes: Int {
        didSet {
            defaults.set(sessionLimitMinutes, forKey: Keys.sessionMinutes)
            onSettingsChanged()
        }
    }

    /// 今日已记录基准时长（来自真实 HealthKit / export.xml）
    @Published var todayBaselineMinutes: Double = 0
    /// 当前连续佩戴实时秒数
    @Published var liveSessionSeconds: Int = 0
    /// 当前是否处于实时计时中
    @Published var isTracking: Bool = false

    @Published var dailyLimitReached: Bool = false
    @Published var sessionLimitReached: Bool = false

    private let defaults = UserDefaults.standard
    private var ticker: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var isHeadphoneConnected: Bool = false
    private var didAlertDaily = false
    private var didAlertSession = false

    private enum Keys {
        static let dailyEnabled = "earphone_useage_daily_limit_enabled"
        static let dailyMinutes = "earphone_useage_daily_limit_minutes"
        static let sessionEnabled = "earphone_useage_session_limit_enabled"
        static let sessionMinutes = "earphone_useage_session_limit_minutes"
    }

    private enum NotificationID {
        static let daily = "earphone_useage_daily_limit_alert"
        static let session = "earphone_useage_session_limit_alert"
    }

    init() {
        let savedDailyMins = defaults.integer(forKey: Keys.dailyMinutes)
        let savedSessionMins = defaults.integer(forKey: Keys.sessionMinutes)

        self.dailyLimitEnabled = defaults.bool(forKey: Keys.dailyEnabled)
        self.dailyLimitMinutes = savedDailyMins > 0 ? savedDailyMins : 180   // 默认 3h
        self.sessionLimitEnabled = defaults.bool(forKey: Keys.sessionEnabled)
        self.sessionLimitMinutes = savedSessionMins > 0 ? savedSessionMins : 60 // 默认 60m
    }

    // MARK: - 实时衍生指标

    var liveTodayMinutes: Double {
        todayBaselineMinutes + Double(liveSessionSeconds) / 60.0
    }

    var liveSessionMinutes: Double {
        Double(liveSessionSeconds) / 60.0
    }

    var dailyProgress: Double {
        guard dailyLimitMinutes > 0 else { return 0 }
        return min(1.0, liveTodayMinutes / Double(dailyLimitMinutes))
    }

    var sessionProgress: Double {
        guard sessionLimitMinutes > 0 else { return 0 }
        return min(1.0, liveSessionMinutes / Double(sessionLimitMinutes))
    }

    // MARK: - 绑定音频路由与真实健康数据

    func bind(audioMonitor: AudioRouteMonitor, dataStore: HealthDataStore) {
        cancellables.removeAll()

        audioMonitor.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                self?.handleConnectionChange(connected)
            }
            .store(in: &cancellables)

        dataStore.$samples
            .sink { [weak self] samples in
                let calendar = Calendar.current
                let todaySamples = samples.filter { calendar.isDateInToday($0.startDate) }
                self?.todayBaselineMinutes = TimeIntervalMerger.mergedMinutes(for: todaySamples)
                self?.evaluateLimits()
                self?.rescheduleNotifications()
            }
            .store(in: &cancellables)
    }

    // MARK: - 自定义限额调整

    func adjustDailyLimit(by deltaMinutes: Int) {
        dailyLimitMinutes = max(30, min(720, dailyLimitMinutes + deltaMinutes))
        didAlertDaily = false
    }

    func adjustSessionLimit(by deltaMinutes: Int) {
        sessionLimitMinutes = max(15, min(360, sessionLimitMinutes + deltaMinutes))
        didAlertSession = false
    }

    // MARK: - 实时计时与后台通知调度

    private func handleConnectionChange(_ connected: Bool) {
        isHeadphoneConnected = connected
        if connected {
            startLiveTracking()
        } else {
            stopLiveTracking()
        }
    }

    private func startLiveTracking() {
        isTracking = true
        didAlertSession = false
        sessionLimitReached = false
        ticker?.cancel()

        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.liveSessionSeconds += 1
                self.evaluateLimits()
            }

        rescheduleNotifications()
    }

    private func stopLiveTracking() {
        isTracking = false
        ticker?.cancel()
        ticker = nil
        liveSessionSeconds = 0
        sessionLimitReached = false
        didAlertSession = false
        cancelAllLimitNotifications()
    }

    private func onSettingsChanged() {
        if dailyLimitEnabled || sessionLimitEnabled {
            requestNotificationPermission()
        }
        evaluateLimits()
        rescheduleNotifications()
    }

    private func evaluateLimits() {
        if dailyLimitEnabled && liveTodayMinutes >= Double(dailyLimitMinutes) {
            dailyLimitReached = true
            if !didAlertDaily {
                didAlertDaily = true
                Haptics.error()
            }
        } else {
            dailyLimitReached = false
        }

        if sessionLimitEnabled && liveSessionMinutes >= Double(sessionLimitMinutes) {
            sessionLimitReached = true
            if !didAlertSession {
                didAlertSession = true
                Haptics.error()
            }
        } else {
            sessionLimitReached = false
        }
    }

    /// 非 .app 包环境（例如 Mac 命令行预览）不能调用 UNUserNotificationCenter.current()，否则会触发 bundleProxyForCurrentProcess is nil 崩溃
    private var supportsUserNotifications: Bool {
        #if os(iOS)
        return true
        #else
        return Bundle.main.bundleURL.pathExtension == "app"
        #endif
    }

    private func requestNotificationPermission() {
        guard supportsUserNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func rescheduleNotifications() {
        guard supportsUserNotifications else { return }
        cancelAllLimitNotifications()
        guard isHeadphoneConnected else { return }

        let center = UNUserNotificationCenter.current()

        if dailyLimitEnabled {
            let remainingSec = (Double(dailyLimitMinutes) - liveTodayMinutes) * 60.0
            if remainingSec > 5 {
                let content = UNMutableNotificationContent()
                content.title = "earuseage"
                content.body = "今日耳机佩戴已达设定限额（\(DurationFormatter.hoursMinutes(minutes: Double(dailyLimitMinutes)))）"
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remainingSec, repeats: false)
                center.add(UNNotificationRequest(identifier: NotificationID.daily, content: content, trigger: trigger))
            }
        }

        if sessionLimitEnabled {
            let remainingSec = (Double(sessionLimitMinutes) - liveSessionMinutes) * 60.0
            if remainingSec > 5 {
                let content = UNMutableNotificationContent()
                content.title = "earuseage"
                content.body = "单次连续佩戴已达设定限额（\(DurationFormatter.hoursMinutes(minutes: Double(sessionLimitMinutes)))）"
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remainingSec, repeats: false)
                center.add(UNNotificationRequest(identifier: NotificationID.session, content: content, trigger: trigger))
            }
        }
    }

    private func cancelAllLimitNotifications() {
        guard supportsUserNotifications else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [NotificationID.daily, NotificationID.session]
        )
    }
}
