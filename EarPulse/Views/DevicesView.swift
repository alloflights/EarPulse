import Combine
import SwiftUI

@MainActor
private final class DevicesViewState: ObservableObject {
    @Published var selectedDevice: HeadphoneUsageSummary? = nil
    @Published var showManageSheet: Bool = false
}

/// 旗舰级液态玻璃「设备」页：
/// 1. 横向滑动大卡片轮播（真实耳机照片/原生图标 + 点击查看详情）
/// 2. 支持自定义排序与合并多个耳机数据
/// 3. 下方保留极简自定义限额提醒卡片
struct DevicesView: View {
    @EnvironmentObject private var dataStore: HealthDataStore
    @EnvironmentObject private var audioMonitor: AudioRouteMonitor
    @EnvironmentObject private var lang: LanguageStore
    @EnvironmentObject private var limitMonitor: UsageLimitMonitor

    @StateObject private var uiState = DevicesViewState()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(audioMonitor.isConnected ? GlassTheme.accentBlue : Color.white.opacity(0.3))
                            .frame(width: 7, height: 7)
                        Text(audioMonitor.connectedDeviceName ?? (audioMonitor.isConnected ? lang.connected : lang.notConnected))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer()

                    if dataStore.deviceSummaries.count >= 2 {
                        Button {
                            Haptics.light()
                            uiState.showManageSheet = true
                        } label: {
                            Label(lang.manageDevices, systemImage: "slider.horizontal.3")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(GlassTheme.softBlue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(GlassTheme.accentBlue.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                if !dataStore.deviceSummaries.isEmpty {
                    headphoneCarousel
                        .staggeredAppear(delay: 0.04)
                }

                usageLimitsCard
                    .padding(.horizontal, 20)
                    .staggeredAppear(delay: 0.12)
            }
            .padding(.top, 8)
            .padding(.bottom, 114)
        }
        .onAppear {
            audioMonitor.refreshCurrentRoute()
        }
        .sheet(item: $uiState.selectedDevice) { device in
            DeviceDetailSheet(device: device)
                .environmentObject(dataStore)
                .environmentObject(lang)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(red: 0.03, green: 0.07, blue: 0.16))
        }
        .sheet(isPresented: $uiState.showManageSheet) {
            DeviceManageSheet()
                .environmentObject(dataStore)
                .environmentObject(lang)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(red: 0.03, green: 0.07, blue: 0.16))
        }
    }

    // MARK: - 横向滑动大卡片轮播
    @ViewBuilder
    private var headphoneCarousel: some View {
        let scroller = ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(dataStore.deviceSummaries) { device in
                    Button {
                        Haptics.light()
                        uiState.selectedDevice = device
                    } label: {
                        carouselDeviceCard(device)
                            .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    #if os(iOS)
                    .scrollTransition { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1.0 : 0.92)
                            .opacity(phase.isIdentity ? 1.0 : 0.72)
                    }
                    #endif
                }
            }
            #if os(iOS)
            .scrollTargetLayout()
            #endif
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
        }
        #if os(iOS)
        scroller.scrollTargetBehavior(.viewAligned)
        #else
        scroller
        #endif
    }

    private func carouselDeviceCard(_ device: HeadphoneUsageSummary) -> some View {
        let total = DurationFormatter.split(minutes: device.totalMinutes)

        return VStack(spacing: 18) {
            HStack {
                Text(lang.categoryTitle(device.category))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }

            AppleHeadphoneIcon(
                category: device.category,
                size: 136,
                animated: device.isPrimary
            )
            .frame(height: 158)

            VStack(spacing: 6) {
                Text(device.deviceName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(total.hours)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(GlassTheme.softBlue)
                    Text("h")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.trailing, 3)
                    Text("\(total.mins)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(GlassTheme.softBlue)
                    Text("min")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Text("\(lang.daysCount(device.activeDays)) · \(Int(round(device.sharePercentage)))% · \(Int(round(device.averageDecibels))) dB")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: 288)
        .liquidGlassCard(cornerRadius: 32, padding: 24, interactive: false)
    }

    // MARK: - 自定义限额提醒卡
    private var usageLimitsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(lang.limitsTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                if limitMonitor.isTracking {
                    Text(formatLiveClock(limitMonitor.liveSessionSeconds))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(GlassTheme.softBlue)
                }
            }

            limitControlRow(
                title: lang.dailyLimit,
                usedText: DurationFormatter.hoursMinutes(minutes: limitMonitor.liveTodayMinutes),
                limitMinutes: limitMonitor.dailyLimitMinutes,
                progress: limitMonitor.dailyProgress,
                isReached: limitMonitor.dailyLimitReached,
                isEnabled: Binding(
                    get: { limitMonitor.dailyLimitEnabled },
                    set: { Haptics.light(); limitMonitor.dailyLimitEnabled = $0 }
                ),
                onDecrease: { Haptics.soft(); limitMonitor.adjustDailyLimit(by: -30) },
                onIncrease: { Haptics.soft(); limitMonitor.adjustDailyLimit(by: 30) }
            )

            Divider().overlay(Color.white.opacity(0.08))

            limitControlRow(
                title: lang.sessionLimit,
                usedText: DurationFormatter.hoursMinutes(minutes: limitMonitor.liveSessionMinutes),
                limitMinutes: limitMonitor.sessionLimitMinutes,
                progress: limitMonitor.sessionProgress,
                isReached: limitMonitor.sessionLimitReached,
                isEnabled: Binding(
                    get: { limitMonitor.sessionLimitEnabled },
                    set: { Haptics.light(); limitMonitor.sessionLimitEnabled = $0 }
                ),
                onDecrease: { Haptics.soft(); limitMonitor.adjustSessionLimit(by: -15) },
                onIncrease: { Haptics.soft(); limitMonitor.adjustSessionLimit(by: 15) }
            )
        }
        .liquidGlassCard(cornerRadius: 28, padding: 22)
    }

    private func limitControlRow(
        title: String,
        usedText: String,
        limitMinutes: Int,
        progress: Double,
        isReached: Bool,
        isEnabled: Binding<Bool>,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        if isReached && isEnabled.wrappedValue {
                            Text(lang.limitReached)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(GlassTheme.accentBlue, in: Capsule())
                        }
                    }

                    Text("\(usedText) / \(DurationFormatter.hoursMinutes(minutes: Double(limitMinutes)))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isEnabled.wrappedValue ? GlassTheme.softBlue : .white.opacity(0.42))
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: onDecrease) {
                        Image(systemName: "minus")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(isEnabled.wrappedValue ? 0.85 : 0.3))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled.wrappedValue)

                    Button(action: onIncrease) {
                        Image(systemName: "plus")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(isEnabled.wrappedValue ? 0.85 : 0.3))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled.wrappedValue)

                    Toggle("", isOn: isEnabled)
                        .labelsHidden()
                        .tint(GlassTheme.accentBlue)
                }
            }

            if isEnabled.wrappedValue {
                GeometryReader { geo in
                    let barW = max(6, max(0, geo.size.width) * CGFloat(min(max(progress, 0), 1)))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(GlassTheme.activeBlueGlass)
                            .frame(width: barW)
                            .shadow(color: GlassTheme.accentBlue.opacity(0.45), radius: 5)
                            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: progress)
                    }
                }
                .frame(height: 5)
            }
        }
    }

    private func formatLiveClock(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 静态无闪烁弹窗背景与轻量卡片样式
private struct StaticSheetBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.10, blue: 0.24),
                Color(red: 0.02, green: 0.05, blue: 0.13)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - 单款耳机详情 Sheet（总使用情况 + 个人纪录 2x2）
private struct DeviceDetailSheet: View {
    let device: HeadphoneUsageSummary
    @EnvironmentObject private var dataStore: HealthDataStore
    @EnvironmentObject private var lang: LanguageStore

    var body: some View {
        let overview = dataStore.overview(forDevice: device.deviceName)
        let records = dataStore.personalRecords(forDevice: device.deviceName)
        let total = DurationFormatter.split(minutes: overview.totalMinutes)
        let daily = DurationFormatter.split(minutes: overview.dailyAverageMinutes)
        let day = DurationFormatter.split(minutes: records.longestDayMinutes)
        let session = DurationFormatter.split(minutes: records.longestSessionMinutes)
        let month = DurationFormatter.split(minutes: records.longestMonthMinutes)

        ZStack {
            StaticSheetBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    AppleHeadphoneIcon(category: device.category, size: 112, animated: true)
                        .frame(height: 132)
                        .padding(.top, 10)

                    VStack(spacing: 6) {
                        Text(device.deviceName)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        Text("\(total.hours)h \(total.mins)min")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(GlassTheme.softBlue)

                        Text("\(lang.daysCount(overview.activeDays)) · \(lang.dailyAvg(hours: daily.hours, mins: daily.mins)) · \(Int(round(overview.weightedAverageDecibels))) dB")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        detailCell(title: lang.bestDay, value: "\(day.hours)h \(day.mins)m")
                        detailCell(title: lang.longestSession, value: "\(session.hours)h \(session.mins)m")
                        detailCell(title: lang.streak, value: lang.daysCount(records.longestStreakDays))
                        detailCell(title: lang.bestMonth, value: "\(month.hours)h \(month.mins)m")
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func detailCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        )
    }
}

// MARK: - 耳机排序与多设备合并 Sheet（静态背景 + 轻量行卡片，消除弹出闪烁）
private struct DeviceManageSheet: View {
    @EnvironmentObject private var dataStore: HealthDataStore
    @EnvironmentObject private var lang: LanguageStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                StaticSheetBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(Array(dataStore.deviceSummaries.enumerated()), id: \.element.id) { index, device in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.deviceName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(device.formattedDuration)
                                        .font(.caption)
                                        .foregroundStyle(GlassTheme.softBlue)
                                }

                                Spacer()

                                HStack(spacing: 6) {
                                    Button {
                                        Haptics.soft()
                                        withAnimation(.snappy(duration: 0.22)) {
                                            dataStore.moveDevice(fromIndex: index, toIndex: max(0, index - 1))
                                        }
                                    } label: {
                                        Image(systemName: "chevron.up")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white.opacity(index == 0 ? 0.28 : 0.88))
                                            .frame(width: 28, height: 28)
                                            .background(Color.white.opacity(0.08), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(index == 0)

                                    Button {
                                        Haptics.soft()
                                        withAnimation(.snappy(duration: 0.22)) {
                                            dataStore.moveDevice(fromIndex: index, toIndex: min(dataStore.deviceSummaries.count - 1, index + 1))
                                        }
                                    } label: {
                                        Image(systemName: "chevron.down")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white.opacity(index == dataStore.deviceSummaries.count - 1 ? 0.28 : 0.88))
                                            .frame(width: 28, height: 28)
                                            .background(Color.white.opacity(0.08), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(index == dataStore.deviceSummaries.count - 1)
                                }

                                if dataStore.deviceSummaries.count > 1 {
                                    Menu {
                                        ForEach(dataStore.deviceSummaries.filter { $0.deviceName != device.deviceName }) { target in
                                            Button("→ \(target.deviceName)") {
                                                Haptics.success()
                                                withAnimation(.snappy(duration: 0.22)) {
                                                    dataStore.mergeDevice(device.deviceName, into: target.deviceName)
                                                }
                                            }
                                        }
                                    } label: {
                                        Text(lang.mergeAction)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(GlassTheme.accentBlue.opacity(0.38), in: Capsule())
                                    }
                                    .menuStyle(.borderlessButton)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.white.opacity(0.07))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                                    )
                            )
                        }

                        if !dataStore.deviceMergeMap.isEmpty || !dataStore.customDeviceOrder.isEmpty {
                            Button {
                                Haptics.light()
                                withAnimation(.snappy(duration: 0.22)) {
                                    dataStore.resetCustomizations()
                                }
                            } label: {
                                Text(lang.unmergeAll)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.10), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                    }
                    .padding(20)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(lang.manageDevices)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.doneLabel) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
