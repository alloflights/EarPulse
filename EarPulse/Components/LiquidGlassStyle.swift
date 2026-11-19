import Combine
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// iOS Taptic Engine 精细震动反馈工具（macOS 预览自动安全空实现）
@MainActor
enum Haptics {
    static func selection() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }

    static func light() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    static func soft() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    static func medium() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    static func success() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }

    static func error() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
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

    /// 液态玻璃左上→右下斜向高光折射描边
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

    /// 激活态蓝色液态胶囊内部高光渐变
    static let activeBlueGlass = LinearGradient(
        colors: [
            softBlue.opacity(0.92),
            accentBlue
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// 多层光学液态玻璃卡片修饰器（折射顶光 + 双层描边 + 深邃悬浮阴影）
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

                    // 顶部玻璃弧面镜面折射光
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

/// 液态玻璃胶囊按钮样式（带按压物理回弹与微光增亮）
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

/// 纯黑底 + 极缓慢流动的深海蓝液态环境光（透过玻璃卡片产生真实明暗折射）
struct LiquidGlassBackdrop: View {
    @StateObject private var state = BackdropDriftState()

    var body: some View {
        ZStack {
            GlassTheme.background

            // 主光斑：顶部柔和深海蓝缓慢呼吸漂移
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
                        endRadius: 260
                    )
                )
                .frame(width: 520, height: 520)
                .offset(
                    x: state.drifted ? 55 : -55,
                    y: state.drifted ? -280 : -320
                )
                .blur(radius: 40)

            // 次光斑：中下部极微弱折射光，给悬浮底栏提供通透感
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            GlassTheme.accentBlue.opacity(0.11),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 200
                    )
                )
                .frame(width: 380, height: 380)
                .offset(
                    x: state.drifted ? -70 : 70,
                    y: state.drifted ? 320 : 270
                )
                .blur(radius: 50)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9.0).repeatForever(autoreverses: true)) {
                state.drifted = true
            }
        }
    }
}

/// 级联弹性入场修饰器（让卡片错峰轻盈浮现）
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
