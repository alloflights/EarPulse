import SwiftUI

/// 新功能：本周听觉健康报告 & 一键生成分享卡片
struct WeeklyReportView: View {
    @EnvironmentObject private var healthManager: HealthKitManager
    @State private var renderedImage: Image?

    var body: some View {
        let report = healthManager.weeklyReport

        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    reportCardView(report: report)

                    if let renderedImage {
                        ShareLink(
                            item: renderedImage,
                            preview: SharePreview("我的本周听觉健康周报", image: renderedImage)
                        ) {
                            Label("分享本周听觉报告卡片", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(report.primaryDeviceCategory.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("听觉周报")
            .onAppear {
                renderShareCard(report: report)
            }
            .onChange(of: healthManager.samples.count) { _, _ in
                renderShareCard(report: healthManager.weeklyReport)
            }
        }
    }

    private func reportCardView(report: WeeklyHearingReport) -> some View {
        let level = ExposureLevel.from(decibels: report.averageDecibels)

        return VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EARPULSE WEEKLY")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text("本周听觉健康报告")
                        .font(.title2.weight(.bold))
                }
                Spacer()
                Text(report.grade)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(level.color.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(spacing: 14) {
                HeadphoneArtworkView(
                    category: report.primaryDeviceCategory,
                    size: 74,
                    glowColor: report.primaryDeviceCategory.accentColor,
                    animateFloating: false,
                    showSoundWaves: false
                )
                .frame(width: 82, height: 82)
                .background(report.primaryDeviceCategory.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("本周主力耳机")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(report.primaryDeviceName)
                        .font(.headline)
                    Text(report.gradeTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(level.color)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                statBox(title: "周均分贝", value: "\(Int(round(report.averageDecibels))) dB", color: level.color)
                statBox(title: "累计聆听", value: String(format: "%.1f h", report.totalHours), color: .primary)
                statBox(title: "安全达标", value: "\(report.safeDaysCount)/7 天", color: .green)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("护耳建议", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.teal)
                Text(report.insightText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func statBox(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @MainActor
    private func renderShareCard(report: WeeklyHearingReport) {
        let renderer = ImageRenderer(
            content: reportCardView(report: report)
                .frame(width: 360)
                .padding(16)
                .background(Color(.systemGroupedBackground))
        )
        renderer.scale = 3.0
        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
    }
}
