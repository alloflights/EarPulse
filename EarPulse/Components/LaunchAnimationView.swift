import SwiftUI

/// App 启动开场动画：当前耳机贴图弹性登场 + 同心声波涟漪 + 品牌标题渐显
struct LaunchAnimationView: View {
    let deviceName: String
    let category: HeadphoneCategory
    let onFinished: () -> Void

    @State private var showArtwork = false
    @State private var expandRipples = false
    @State private var showTitle = false
    @State private var fadeOut = false

    var body: some View {
        ZStack {
            // 清新极简背景（自适应浅色/深色模式）
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    category.accentColor.opacity(0.08),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    // 开场同心声波涟漪
                    ForEach(0..<3, id: \.self) { idx in
                        Circle()
                            .stroke(
                                category.accentColor.opacity(expandRipples ? 0.0 : 0.32),
                                lineWidth: 2.5
                            )
                            .frame(width: 150, height: 150)
                            .scaleEffect(expandRipples ? 2.1 + CGFloat(idx) * 0.35 : 0.65)
                            .animation(
                                .easeOut(duration: 1.5).delay(0.15 + Double(idx) * 0.22),
                                value: expandRipples
                            )
                    }

                    // 磨砂玻璃圆形底座
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 190, height: 190)
                        .shadow(color: category.accentColor.opacity(0.18), radius: 24, x: 0, y: 12)
                        .scaleEffect(showArtwork ? 1.0 : 0.72)
                        .opacity(showArtwork ? 1.0 : 0.0)

                    // 当前耳机 3D 贴图
                    HeadphoneArtworkView(
                        category: category,
                        size: 136,
                        glowColor: category.accentColor,
                        animateFloating: true,
                        showSoundWaves: false
                    )
                    .scaleEffect(showArtwork ? 1.0 : 0.55)
                    .offset(y: showArtwork ? 0 : 48)
                    .opacity(showArtwork ? 1.0 : 0.0)
                }

                VStack(spacing: 10) {
                    Text("EarPulse · 聆听护盾")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Image(systemName: category.sfSymbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(category.accentColor)
                        Text("正在载入 \(deviceName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .opacity(showTitle ? 1.0 : 0.0)
                .offset(y: showTitle ? 0 : 14)

                Spacer()

                Text("基于 Apple HealthKit 听觉健康保护")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .opacity(showTitle ? 1.0 : 0.0)
                    .padding(.bottom, 24)
            }
            .padding()
        }
        .opacity(fadeOut ? 0.0 : 1.0)
        .scaleEffect(fadeOut ? 1.04 : 1.0)
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.72)) {
                showArtwork = true
            }
            expandRipples = true
            withAnimation(.easeOut(duration: 0.55).delay(0.32)) {
                showTitle = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) {
                withAnimation(.easeInOut(duration: 0.42)) {
                    fadeOut = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                    onFinished()
                }
            }
        }
    }
}
