import SwiftUI

/// 苹果极简 3D 质感耳机贴图视图（支持动态悬浮、3D 微旋、声波光环）
struct HeadphoneArtworkView: View {
    let category: HeadphoneCategory
    var size: CGFloat = 120
    var glowColor: Color = .teal
    var animateFloating: Bool = true
    var showSoundWaves: Bool = false

    @State private var isFloating = false
    @State private var wavePulse = false

    var body: some View {
        ZStack {
            if showSoundWaves {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(glowColor.opacity(wavePulse ? 0.0 : 0.28), lineWidth: 2)
                        .frame(width: size * 0.92, height: size * 0.92)
                        .scaleEffect(wavePulse ? 1.55 + CGFloat(index) * 0.22 : 0.88)
                        .animation(
                            .easeOut(duration: 2.2)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.6),
                            value: wavePulse
                        )
                }
            }

            // 底部柔和环境光晕
            Circle()
                .fill(
                    RadialGradient(
                        colors: [glowColor.opacity(0.24), glowColor.opacity(0.0)],
                        center: .center,
                        startRadius: size * 0.08,
                        endRadius: size * 0.62
                    )
                )
                .frame(width: size * 1.25, height: size * 1.25)

            // 精致耳机本体贴图
            artworkBody
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.14), radius: size * 0.1, x: 0, y: size * 0.08)
                .offset(y: animateFloating && isFloating ? -size * 0.045 : size * 0.02)
                .rotation3DEffect(
                    .degrees(animateFloating && isFloating ? 8 : -8),
                    axis: (x: 0.15, y: 1.0, z: 0.0)
                )
                .animation(
                    animateFloating
                        ? .easeInOut(duration: 2.6).repeatForever(autoreverses: true)
                        : .default,
                    value: isFloating
                )
        }
        .onAppear {
            if animateFloating {
                isFloating = true
            }
            if showSoundWaves {
                wavePulse = true
            }
        }
    }

    @ViewBuilder
    private var artworkBody: some View {
        switch category {
        case .airPodsPro:
            AirPodsProSticker(size: size)
        case .airPodsMax:
            AirPodsMaxSticker(size: size)
        case .airPods:
            AirPodsClassicSticker(size: size)
        case .overEar:
            OverEarStudioSticker(size: size)
        case .wired:
            WiredEarPodsSticker(size: size)
        }
    }
}

// MARK: - 1. AirPods Pro 贴图
private struct AirPodsProSticker: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // 左耳
            singleBud(mirrored: false)
                .offset(x: -size * 0.21, y: -size * 0.02)
                .rotationEffect(.degrees(-8))

            // 右耳
            singleBud(mirrored: true)
                .offset(x: size * 0.21, y: size * 0.03)
                .rotationEffect(.degrees(8))
        }
    }

    private func singleBud(mirrored: Bool) -> some View {
        let s = size
        return ZStack {
            // 耳机柄
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(white: 0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: s * 0.11, height: s * 0.42)
                .offset(x: mirrored ? -s * 0.04 : s * 0.04, y: s * 0.18)

            // 底部金属触点
            Capsule()
                .fill(Color(white: 0.72))
                .frame(width: s * 0.09, height: s * 0.035)
                .offset(x: mirrored ? -s * 0.04 : s * 0.04, y: s * 0.37)

            // 腔体主体
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.white, Color(white: 0.90)],
                        center: .topLeading,
                        startRadius: s * 0.02,
                        endRadius: s * 0.26
                    )
                )
                .frame(width: s * 0.30, height: s * 0.26)
                .offset(y: -s * 0.04)

            // 黑色声学通气孔
            Capsule()
                .fill(Color(white: 0.18))
                .frame(width: s * 0.08, height: s * 0.035)
                .offset(x: mirrored ? -s * 0.03 : s * 0.03, y: -s * 0.07)

            // 硅胶耳塞头
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.96), Color(white: 0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: s * 0.14, height: s * 0.21)
                .offset(x: mirrored ? s * 0.15 : -s * 0.15, y: -s * 0.05)
        }
    }
}

// MARK: - 2. AirPods Max 贴图
private struct AirPodsMaxSticker: View {
    let size: CGFloat

    var body: some View {
        let s = size
        ZStack {
            // 穹网头梁
            Circle()
                .trim(from: 0.54, to: 0.96)
                .stroke(
                    LinearGradient(
                        colors: [Color(white: 0.82), Color(white: 0.96), Color(white: 0.78)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: s * 0.095, lineCap: .round)
                )
                .frame(width: s * 0.72, height: s * 0.72)
                .offset(y: -s * 0.02)

            // 金属伸缩支臂
            RoundedRectangle(cornerRadius: s * 0.02)
                .fill(Color(white: 0.75))
                .frame(width: s * 0.045, height: s * 0.20)
                .offset(x: -s * 0.31, y: s * 0.02)

            RoundedRectangle(cornerRadius: s * 0.02)
                .fill(Color(white: 0.75))
                .frame(width: s * 0.045, height: s * 0.20)
                .offset(x: s * 0.31, y: s * 0.02)

            // 左耳罩
            earCup(size: s, isLeft: true)
                .offset(x: -s * 0.29, y: s * 0.19)

            // 右耳罩
            earCup(size: s, isLeft: false)
                .offset(x: s * 0.29, y: s * 0.19)
        }
    }

    private func earCup(size s: CGFloat, isLeft: Bool) -> some View {
        ZStack {
            // 阳极氧化铝外壳
            RoundedRectangle(cornerRadius: s * 0.11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.95), Color(white: 0.79)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: s * 0.24, height: s * 0.38)

            // 织物耳垫内衬
            RoundedRectangle(cornerRadius: s * 0.09, style: .continuous)
                .fill(Color(white: 0.88))
                .frame(width: s * 0.08, height: s * 0.34)
                .offset(x: isLeft ? s * 0.11 : -s * 0.11)

            // 数码旋钮（右耳顶部）
            if !isLeft {
                RoundedRectangle(cornerRadius: s * 0.015)
                    .fill(Color(white: 0.66))
                    .frame(width: s * 0.055, height: s * 0.03)
                    .offset(x: s * 0.02, y: -s * 0.20)
            }
        }
    }
}

// MARK: - 3. AirPods 经典款贴图
private struct AirPodsClassicSticker: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            classicPod(mirrored: false)
                .offset(x: -size * 0.20, y: 0)
                .rotationEffect(.degrees(-6))
            classicPod(mirrored: true)
                .offset(x: size * 0.20, y: size * 0.03)
                .rotationEffect(.degrees(6))
        }
    }

    private func classicPod(mirrored: Bool) -> some View {
        let s = size
        return ZStack {
            // 细长耳机柄
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(white: 0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: s * 0.095, height: s * 0.54)
                .offset(x: mirrored ? -s * 0.03 : s * 0.03, y: s * 0.15)

            // 银色底部环
            Capsule()
                .fill(Color(white: 0.72))
                .frame(width: s * 0.085, height: s * 0.04)
                .offset(x: mirrored ? -s * 0.03 : s * 0.03, y: s * 0.40)

            // 半入耳腔体
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.white, Color(white: 0.89)],
                        center: .topLeading,
                        startRadius: s * 0.02,
                        endRadius: s * 0.24
                    )
                )
                .frame(width: s * 0.25, height: s * 0.27)
                .offset(y: -s * 0.12)

            // 扬声器网孔
            Ellipse()
                .fill(Color(white: 0.22))
                .frame(width: s * 0.06, height: s * 0.11)
                .offset(x: mirrored ? s * 0.07 : -s * 0.07, y: -s * 0.12)
        }
    }
}

// MARK: - 4. 通用蓝牙头戴式耳机贴图（磨砂深空灰）
private struct OverEarStudioSticker: View {
    let size: CGFloat

    var body: some View {
        let s = size
        ZStack {
            Circle()
                .trim(from: 0.53, to: 0.97)
                .stroke(
                    LinearGradient(
                        colors: [Color(white: 0.28), Color(white: 0.42), Color(white: 0.22)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: s * 0.10, lineCap: .round)
                )
                .frame(width: s * 0.72, height: s * 0.72)
                .offset(y: -s * 0.03)

            // 左耳罩
            studioCup(size: s, isLeft: true)
                .offset(x: -s * 0.29, y: s * 0.18)

            // 右耳罩
            studioCup(size: s, isLeft: false)
                .offset(x: s * 0.29, y: s * 0.18)
        }
    }

    private func studioCup(size s: CGFloat, isLeft: Bool) -> some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.34), Color(white: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: s * 0.23, height: s * 0.38)

            // 皮革耳垫
            Capsule()
                .fill(Color(white: 0.12))
                .frame(width: s * 0.08, height: s * 0.35)
                .offset(x: isLeft ? s * 0.10 : -s * 0.10)

            // 侧边微光装饰环
            Circle()
                .stroke(Color.purple.opacity(0.65), lineWidth: s * 0.015)
                .frame(width: s * 0.08, height: s * 0.08)
                .offset(x: isLeft ? -s * 0.03 : s * 0.03)
        }
    }
}

// MARK: - 5. 有线 EarPods 贴图
private struct WiredEarPodsSticker: View {
    let size: CGFloat

    var body: some View {
        let s = size
        ZStack {
            // 柔和线缆弧线
            Path { path in
                path.move(to: CGPoint(x: s * 0.30, y: s * 0.65))
                path.addCurve(
                    to: CGPoint(x: s * 0.50, y: s * 0.90),
                    control1: CGPoint(x: s * 0.30, y: s * 0.84),
                    control2: CGPoint(x: s * 0.42, y: s * 0.88)
                )
                path.move(to: CGPoint(x: s * 0.70, y: s * 0.65))
                path.addCurve(
                    to: CGPoint(x: s * 0.50, y: s * 0.90),
                    control1: CGPoint(x: s * 0.70, y: s * 0.84),
                    control2: CGPoint(x: s * 0.58, y: s * 0.88)
                )
            }
            .stroke(Color(white: 0.78), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))

            AirPodsClassicSticker(size: s * 0.82)
                .offset(y: -s * 0.06)
        }
    }
}
