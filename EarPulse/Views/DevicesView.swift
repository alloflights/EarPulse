import SwiftUI

/// 旗舰级液态玻璃「设备」页（舞台光晕 + 级联浮现 + 微光进度条）
struct DevicesView: View {
    @EnvironmentObject private var dataStore: HealthDataStore
    @EnvironmentObject private var audioMonitor: AudioRouteMonitor
    @EnvironmentObject private var lang: LanguageStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 26) {
                currentConnectionCard
                    .staggeredAppear(delay: 0.04)
                    .scrollTransition { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1.0 : 0.96)
                            .opacity(phase.isIdentity ? 1.0 : 0.84)
                    }

                if !dataStore.deviceSummaries.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(lang.byDevice)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))

                        ForEach(dataStore.deviceSummaries) { device in
                            deviceRow(device)
                        }
                    }
                    .liquidGlassCard(cornerRadius: 28, padding: 22)
                    .staggeredAppear(delay: 0.12)
                    .scrollTransition { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1.0 : 0.96)
                            .opacity(phase.isIdentity ? 1.0 : 0.84)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 114)
        }
        .onAppear {
            audioMonitor.refreshCurrentRoute()
        }
    }

    private var currentConnectionCard: some View {
        let displayCategory: HeadphoneCategory = audioMonitor.isConnected
            ? audioMonitor.connectedCategory
            : (dataStore.mostUsedDevice?.category ?? .airPodsPro)

        return VStack(spacing: 20) {
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(audioMonitor.isConnected ? GlassTheme.accentBlue : Color.white.opacity(0.28))
                        .frame(width: 7, height: 7)
                        .shadow(color: audioMonitor.isConnected ? GlassTheme.accentBlue : .clear, radius: 5)
                    Text(audioMonitor.isConnected ? lang.connected : lang.notConnected)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
            }

            AppleHeadphoneIcon(
                category: displayCategory,
                size: 118,
                animated: true
            )
            .frame(height: 142)

            VStack(spacing: 6) {
                if let name = audioMonitor.connectedDeviceName {
                    Text(name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                } else if let top = dataStore.mostUsedDevice {
                    Text(top.deviceName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(top.formattedDuration)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(GlassTheme.softBlue)
                } else {
                    Text(lang.notConnected)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .liquidGlassCard(cornerRadius: 30, padding: 26)
    }

    private func deviceRow(_ device: HeadphoneUsageSummary) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                AppleHeadphoneIcon(category: device.category, size: 38, animated: false)
                    .frame(width: 54, height: 54)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(GlassTheme.glassRimGradient, lineWidth: 0.9)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(device.deviceName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(lang.categoryTitle(device.category)) · \(lang.daysCount(device.activeDays))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(device.formattedDuration)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(GlassTheme.softBlue)
                    Text("\(Int(round(device.sharePercentage)))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.42))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(GlassTheme.activeBlueGlass)
                        .frame(width: max(6, geo.size.width * CGFloat(device.sharePercentage / 100.0)))
                        .shadow(color: GlassTheme.accentBlue.opacity(0.45), radius: 5, x: 0, y: 0)
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 6)
    }
}
