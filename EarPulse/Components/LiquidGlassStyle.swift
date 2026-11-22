import Combine
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// iOS Taptic Engine + macOS Force Touch 双端震动反馈
@MainActor
enum Haptics {
    #if os(iOS)
    private static let selectionGen = UISelectionFeedbackGenerator()
    private static let lightGen = UIImpactFeedbackGenerator(style: .light)
    private static let softGen = UIImpactFeedbackGenerator(style: .soft)
    private static let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private static let notificationGen = UINotificationFeedbackGenerator()
    #endif

    static func selection() {
        #if os(iOS)
        selectionGen.selectionChanged()
        selectionGen.prepare()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }

    static func light() {
        #if os(iOS)
        lightGen.impactOccurred(intensity: 0.9)
        lightGen.prepare()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }

    static func soft() {
        #if os(iOS)
        softGen.impactOccurred(intensity: 0.8)
        softGen.prepare()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }

    static func medium() {
        #if os(iOS)
        mediumGen.impactOccurred(intensity: 1.0)
        mediumGen.prepare()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }

    static func success() {
        #if os(iOS)
        notificationGen.notificationOccurred(.success)
        notificationGen.prepare()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }

    static func error() {
        #if os(iOS)
        notificationGen.notificationOccurred(.error)
        notificationGen.prepare()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }
}

/// 统一黑蓝光学液态玻璃配色体系（含分耳机冷色系图表色板）
enum GlassTheme {
    static let accentBlue = Color(red: 0.24, green: 0.59, blue: 1.0)
    static let deepBlue = Color(red: 0.05, green: 0.20, blue: 0.54)
    static let softBlue = Color(red: 0.60, green: 0.82, blue: 1.0)
    static let glowCoreBlue = softBlue

    /// 逐小时分耳机堆叠柱状图色板（克制的蓝/青/靛/银冷色调）
    static let deviceChartPalette: [Color] = [
        Color(red: 0.24, green: 0.59, blue: 1.0),   // Apple Blue
        Color(red: 0.32, green: 0.82, blue: 0.96),  // Ice Cyan
        Color(red: 0.48, green: 0.45, blue: 0.98),  // Electric Indigo
        Color(red: 0.72, green: 0.84, blue: 0.98),  // Silver Blue
        Color(red: 0.16, green: 0.42, blue: 0.82)   // Cobalt
    ]

    static func deviceColor(at index: Int) -> Color {
        deviceChartPalette[index % deviceChartPalette.count]
    }

    static let glassRimGradient = LinearGradient(
        stops: [
            .init(color: Color.white.opacity(0.42), location: 0.0),
            .init(color: Color.white.opacity(0.10), location: 0.30),
            .init(color: accentBlue.opacity(0.28), location: 0.68),
            .init(color: Color.white.opacity(0.12), location: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let activeBlueGlass = LinearGradient(
        colors: [softBlue.opacity(0.92), accentBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// 真正 iOS 26/27 原生 Liquid Glass 卡片修饰器（#available(iOS 26, macOS 26, *) 调用真 .glassEffect，低版本优雅降级）
struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 28
    var padding: CGFloat = 22
    var interactive: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        let padded = content.padding(padding)
        if #available(iOS 26.0, macOS 26.0, *) {
            padded
                .glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            padded
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(GlassTheme.glassRimGradient, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
        }
    }
}

/// 真正 iOS 26/27 原生 Liquid Glass 胶囊按钮样式
struct LiquidGlassPillButtonStyle: ButtonStyle {
    var prominent: Bool = false

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)

        if #available(iOS 26.0, macOS 26.0, *) {
            label
                .glassEffect(
                    prominent
                        ? .regular.tint(GlassTheme.accentBlue).interactive()
                        : .regular.interactive(),
                    in: .capsule
                )
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
        } else {
            label
                .background {
                    Capsule().fill(prominent ? AnyShapeStyle(GlassTheme.activeBlueGlass) : AnyShapeStyle(.ultraThinMaterial))
                }
                .overlay(Capsule().strokeBorder(GlassTheme.glassRimGradient, lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
        }
    }
}

@MainActor
private final class BackdropDriftState: ObservableObject {
    @Published var phase = false
}

/// 上一版经典深海蓝光效流光背景（MeshGradient 在 iOS 18+ / macOS 15+ 原生渲染，低版本自动降级为线性渐变防崩溃）
struct LiquidGlassBackdrop: View {
    @StateObject private var state = BackdropDriftState()

    var body: some View {
        ZStack {
            if #available(iOS 18.0, macOS 15.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [0.0, 0.5], [state.phase ? 0.62 : 0.38, state.phase ? 0.42 : 0.56], [1.0, 0.5],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                    ],
                    colors: [
                        Color(red: 0.02, green: 0.05, blue: 0.14),
                        Color(red: 0.06, green: 0.20, blue: 0.48),
                        Color(red: 0.02, green: 0.06, blue: 0.18),

                        Color(red: 0.03, green: 0.10, blue: 0.28),
                        Color(red: 0.12, green: 0.36, blue: 0.78),
                        Color(red: 0.03, green: 0.08, blue: 0.22),

                        Color(red: 0.01, green: 0.02, blue: 0.07),
                        Color(red: 0.04, green: 0.15, blue: 0.38),
                        Color(red: 0.01, green: 0.03, blue: 0.10)
                    ]
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.10, blue: 0.28),
                        Color(red: 0.06, green: 0.20, blue: 0.48),
                        Color(red: 0.01, green: 0.03, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height

                ZStack {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    GlassTheme.softBlue.opacity(0.32),
                                    GlassTheme.accentBlue.opacity(0.14),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: w * 0.55
                            )
                        )
                        .frame(width: w * 1.1, height: h * 0.36)
                        .rotationEffect(.degrees(-18))
                        .position(
                            x: state.phase ? w * 0.72 : w * 0.28,
                            y: state.phase ? h * 0.20 : h * 0.14
                        )
                        .blur(radius: 36)

                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    GlassTheme.accentBlue.opacity(0.28),
                                    Color(red: 0.32, green: 0.78, blue: 1.0).opacity(0.10),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: w * 0.50
                            )
                        )
                        .frame(width: w * 1.0, height: h * 0.32)
                        .rotationEffect(.degrees(16))
                        .position(
                            x: state.phase ? w * 0.25 : w * 0.75,
                            y: state.phase ? h * 0.84 : h * 0.76
                        )
                        .blur(radius: 42)
                }
                .frame(width: w, height: h)
            }
        }
        .clipped()
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8.5).repeatForever(autoreverses: true)) {
                state.phase = true
            }
        }
    }
}

@MainActor
private final class StaggerAppearState: ObservableObject {
    @Published var visible = false
}

struct StaggeredGlassAppear: ViewModifier {
    let delay: Double
    @StateObject private var state = StaggerAppearState()

    func body(content: Content) -> some View {
        content
            .opacity(state.visible ? 1.0 : 0.0)
            .offset(y: state.visible ? 0 : 12)
            .scaleEffect(state.visible ? 1.0 : 0.98)
            .onAppear {
                withAnimation(.spring(response: 0.54, dampingFraction: 0.84).delay(delay)) {
                    state.visible = true
                }
            }
    }
}

extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 28, padding: CGFloat = 22, interactive: Bool = false) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, padding: padding, interactive: interactive))
    }

    func staggeredAppear(delay: Double) -> some View {
        modifier(StaggeredGlassAppear(delay: delay))
    }
}
