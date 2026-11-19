import Combine
import SwiftUI

/// 新功能：60-60 护耳番茄钟 + 交互式分贝场景安全尺
struct ProtectionToolsView: View {
    // 60-60 护耳计时器状态
    @State private var selectedPresetMinutes: Int = 45
    @State private var remainingSeconds: Int = 45 * 60
    @State private var isTimerRunning: Bool = false
    @State private var isRestMode: Bool = false

    // 交互式分贝安全模拟尺状态
    @State private var simulatedDecibels: Double = 72

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let presets: [(label: String, minutes: Int, rest: Bool)] = [
        ("轻享 25m", 25, false),
        ("通勤 45m", 45, false),
        ("60-60 上限", 60, false),
        ("休息 5m", 5, true)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    focusTimerCard
                    decibelScaleCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("护耳工具")
            .onReceive(timer) { _ in
                guard isTimerRunning else { return }
                if remainingSeconds > 0 {
                    remainingSeconds -= 1
                } else {
                    isTimerRunning = false
                }
            }
        }
    }

    // MARK: - 1. 60-60 护耳番茄钟
    private var focusTimerCard: some View {
        let total = max(1, selectedPresetMinutes * 60)
        let progress = Double(remainingSeconds) / Double(total)
        let themeColor: Color = isRestMode ? .green : .blue

        return VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("60-60 听觉护耳计时")
                        .font(.headline)
                    Text("音量 ≤ 60%，连续佩戴不超过 60 分钟")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(isRestMode ? "摘下耳机休息" : "安全聆听中")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(themeColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(themeColor.opacity(0.12), in: Capsule())
            }

            // 圆形倒计时进度环
            ZStack {
                Circle()
                    .stroke(themeColor.opacity(0.14), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(themeColor.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.4), value: progress)

                VStack(spacing: 4) {
                    Text(formatClock(remainingSeconds))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(isRestMode ? "让耳蜗安静恢复" : "到点提醒摘下休息 5 分钟")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 174, height: 174)
            .padding(.vertical, 4)

            // 预设时长按钮
            HStack(spacing: 8) {
                ForEach(presets, id: \.label) { preset in
                    let selected = selectedPresetMinutes == preset.minutes && isRestMode == preset.rest
                    Button(preset.label) {
                        isTimerRunning = false
                        selectedPresetMinutes = preset.minutes
                        remainingSeconds = preset.minutes * 60
                        isRestMode = preset.rest
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        selected ? themeColor : Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .foregroundStyle(selected ? .white : .primary)
                }
            }

            // 开始 / 重置控制
            HStack(spacing: 12) {
                Button {
                    isTimerRunning.toggle()
                } label: {
                    Label(isTimerRunning ? "暂停计时" : "开始护耳计时", systemImage: isTimerRunning ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .tint(themeColor)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    isTimerRunning = false
                    remainingSeconds = selectedPresetMinutes * 60
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 11)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.bordered)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - 2. 交互式分贝场景安全尺
    private var decibelScaleCard: some View {
        let level = ExposureLevel.from(decibels: simulatedDecibels)
        let safeMinutes = AcousticDoseCalculator.dailySafeMinutes(at: simulatedDecibels)
        let scene = sceneDescription(for: simulatedDecibels)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("分贝安全模拟尺")
                        .font(.headline)
                    Text("拖动滑块查看不同音量对应的 WHO 每日安全上限")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(round(simulatedDecibels)))")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(level.color)
                Text("dB")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("每日安全上限")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(AcousticDoseCalculator.formatSafeDuration(minutes: safeMinutes))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(level.color)
                }
            }

            Slider(value: $simulatedDecibels, in: 45...105, step: 1)
                .tint(level.color)

            HStack(spacing: 10) {
                Image(systemName: scene.icon)
                    .font(.title3)
                    .foregroundStyle(level.color)
                    .frame(width: 36, height: 36)
                    .background(level.color.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("约等于：\(scene.title)")
                        .font(.subheadline.weight(.semibold))
                    Text(level.shortAdvice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func formatClock(_ totalSeconds: Int) -> String {
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func sceneDescription(for db: Double) -> (title: String, icon: String) {
        switch db {
        case ..<55: return ("安静图书馆 / 轻声细语", "books.vertical.fill")
        case 55..<68: return ("室内轻柔交谈 / 舒适音乐", "bubble.left.and.bubble.right.fill")
        case 68..<78: return ("咖啡馆背景音 / 办公环境", "cup.and.saucer.fill")
        case 78..<86: return ("城市主干道 / 地铁车厢", "tram.fill")
        case 86..<95: return ("繁忙施工 / 高音量耳机", "speaker.wave.3.fill")
        default: return ("Livehouse / 演唱会现场", "music.mic")
        }
    }
}
