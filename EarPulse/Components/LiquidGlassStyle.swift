import Combine
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// iOS Taptic Engine（常驻预热实例）+ macOS Force Touch 触控板双端震动反馈
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

/// 统一视觉系统：纯黑底 + 苹果蓝唯一强调色 + 多层光学液态玻璃（Liquid Glass）
enum GlassTheme {
    static let background = Color.black
    static let accentBlue = Color(red: 0.22, green: 0.57, blue: 1.0)
    static let deepBlue = Color(red: 0.06, green: 0.22, blue: 0.56)
    static let softBlue = Color(red: 0.58, green: 0.80, blue: 1.0)
    static let glassFill = Color.white.opacity(0.055)

    static let glassRimGradient = LinearGradient(
        stops: [
            .init(color: Color.white.opacity(0.36), location: 0.0),
            .init(color: Color.white.opacity(0.10), location: 0.28),
            .init(color: accentBlue.opacity(0.24), location: 0.65),
            .init(color: Color.white.opacity(0.08), location: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let activeBlueGlass = LinearGradient(
        colors: [
            softBlue.opacity(0.92),
            accentBlue
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// 多层光学液态玻璃卡片修饰器
struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 28
    var padding: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(GlassTheme.glassFill)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.15), location: 0.0),
                                    .init(color: Color.white.opacity(0.03), location: 0.22),
                                    .init(color: Color.clear, location: 0.55)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(GlassTheme.glassRimGradient, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius + 0.5, style: .continuous)
                    .stroke(Color.black.opacity(0.45), lineWidth: 0.6)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 22, x: 0, y: 12)
    }
}

/// 液态玻璃胶囊按钮样式
struct LiquidGlassPillButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background {
                ZStack {
                    if prominent {
                        Capsule().fill(GlassTheme.activeBlueGlass)
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08))
                    }
                }
                .overlay(
                    Capsule()
                        .strokeBorder(
                            prominent
                                ? AnyShapeStyle(Color.white.opacity(0.40))
                                : AnyShapeStyle(GlassTheme.glassRimGradient),
                            lineWidth: 1
                        )
                )
            }
            .shadow(
                color: prominent ? GlassTheme.accentBlue.opacity(configuration.isPressed ? 0.2 : 0.35) : Color.black.opacity(0.35),
                radius: configuration.isPressed ? 8 : 16,
                x: 0,
                y: configuration.isPressed ? 3 : 8
            )
            .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

@MainActor
private final class BackdropDriftState: ObservableObject {
    @Published var drifted = false
}

/// 纯黑底 + 流动深海蓝环境光（严格裁剪在屏幕边界内，绝不撑大外部 ZStack 宽度）
struct LiquidGlassBackdrop: View {
    @StateObject private var state = BackdropDriftState()

    var body: some View {
        GlassTheme.background
            .overlay {
                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height

                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        GlassTheme.accentBlue.opacity(0.24),
                                        GlassTheme.deepBlue.opacity(0.10),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: w * 0.68
                                )
                            )
                            .frame(width: w * 1.35, height: w * 1.35)
                            .position(
                                x: state.drifted ? w * 0.62 : w * 0.38,
                                y: state.drifted ? h * 0.14 : h * 0.08
                            )
                            .blur(radius: 36)

                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        GlassTheme.accentBlue.opacity(0.12),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: w * 0.52
                                )
                            )
                            .frame(width: w * 1.0, height: w * 1.0)
                            .position(
                                x: state.drifted ? w * 0.32 : w * 0.68,
                                y: state.drifted ? h * 0.88 : h * 0.82
                            )
                            .blur(radius: 44)
                    }
                    .frame(width: w, height: h)
                }
            }
            .clipped()
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 9.0).repeatForever(autoreverses: true)) {
                    state.drifted = true
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
            .offset(y: state.visible ? 0 : 14)
            .scaleEffect(state.visible ? 1.0 : 0.975)
            .onAppear {
                withAnimation(.spring(response: 0.58, dampingFraction: 0.84).delay(delay)) {
                    state.visible = true
                }
            }
    }
}

extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 28, padding: CGFloat = 22) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    func staggeredAppear(delay: Double) -> some View {
        modifier(StaggeredGlassAppear(delay: delay))
    }
}
