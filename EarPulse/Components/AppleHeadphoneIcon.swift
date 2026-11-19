import Combine
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
private final class FloatingAnimState: ObservableObject {
    @Published var isFloating = false
}

@MainActor
private final class LaunchAnimState: ObservableObject {
    @Published var appeared = false
    @Published var dismissed = false
}

/// Apple 官方设备优先加载官网产品图（带舞台光晕与柔和 3D 悬浮），其他品牌仅区分头戴/入耳原生图标
struct AppleHeadphoneIcon: View {
    let category: HeadphoneCategory
    var size: CGFloat = 72
    var animated: Bool = false

    @StateObject private var anim = FloatingAnimState()

    var body: some View {
        ZStack {
            if animated {
                // 柔和液态蓝背景光晕
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                GlassTheme.accentBlue.opacity(anim.isFloating ? 0.30 : 0.14),
                                GlassTheme.deepBlue.opacity(anim.isFloating ? 0.12 : 0.04),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: size * 0.08,
                            endRadius: size * 0.92
                        )
                    )
                    .frame(width: size * 1.75, height: size * 1.75)
                    .scaleEffect(anim.isFloating ? 1.07 : 0.93)

                // 底部舞台反射投影
                Ellipse()
                    .fill(GlassTheme.accentBlue.opacity(anim.isFloating ? 0.14 : 0.24))
                    .frame(width: size * 0.72, height: size * 0.13)
                    .blur(radius: 8)
                    .offset(y: size * 0.56)
            }

            deviceVisual
                .frame(width: size, height: size)
                .shadow(color: GlassTheme.accentBlue.opacity(animated ? 0.32 : 0.10), radius: 18, x: 0, y: 10)
                .offset(y: animated && anim.isFloating ? -5 : 2)
                .rotation3DEffect(
                    .degrees(animated && anim.isFloating ? 10 : -10),
                    axis: (x: 0.06, y: 1.0, z: 0.0),
                    perspective: 0.65
                )
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                anim.isFloating = true
            }
        }
    }

    private func hasLocalAsset(_ name: String) -> Bool {
        #if os(iOS)
        return UIImage(named: name) != nil
        #elseif os(macOS)
        return NSImage(named: name) != nil
        #else
        return false
        #endif
    }

    @ViewBuilder
    private var deviceVisual: some View {
        if category.isAppleOfficial {
            if let assetName = category.localAssetName, hasLocalAsset(assetName) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else if let url = category.officialAppleImageURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.35))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        fallbackSymbol
                    }
                }
            } else {
                fallbackSymbol
            }
        } else {
            fallbackSymbol
        }
    }

    private var fallbackSymbol: some View {
        Image(systemName: category.sfSymbol)
            .font(.system(size: size * 0.62, weight: .light))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white, GlassTheme.softBlue)
    }
}

/// 仿 iOS 液态玻璃弹窗风格的极简启动动效
struct MinimalLaunchOverlay: View {
    let deviceName: String?
    let category: HeadphoneCategory
    let onFinished: () -> Void

    @StateObject private var anim = LaunchAnimState()

    var body: some View {
        ZStack {
            LiquidGlassBackdrop()

            VStack(spacing: 22) {
                AppleHeadphoneIcon(category: category, size: 96, animated: true)
                    .scaleEffect(anim.appeared ? 1.0 : 0.78)
                    .opacity(anim.appeared ? 1.0 : 0.0)

                VStack(spacing: 6) {
                    Text("earphone useage")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    if let deviceName {
                        Text(deviceName)
                            .font(.subheadline)
                            .foregroundStyle(GlassTheme.softBlue)
                    }
                }
                .opacity(anim.appeared ? 1.0 : 0.0)
                .offset(y: anim.appeared ? 0 : 8)
            }
            .padding(.horizontal, 42)
            .padding(.vertical, 38)
            .liquidGlassCard(cornerRadius: 36, padding: 20)
            .scaleEffect(anim.appeared ? 1.0 : 0.90)
            .blur(radius: anim.dismissed ? 8 : 0)
        }
        .opacity(anim.dismissed ? 0.0 : 1.0)
        .onAppear {
            withAnimation(.spring(response: 0.56, dampingFraction: 0.78)) {
                anim.appeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                withAnimation(.easeInOut(duration: 0.32)) {
                    anim.dismissed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    onFinished()
                }
            }
        }
    }
}
