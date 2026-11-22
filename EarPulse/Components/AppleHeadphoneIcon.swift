import AVFoundation
import Combine
import SwiftUI
#if os(iOS)
import AVFAudio
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
private final class FloatingAnimState: ObservableObject {
    @Published var isFloating = false
}

@MainActor
private final class AirPodsLaunchState: ObservableObject {
    @Published var cardUp = false
    @Published var visualVisible = false
    @Published var dismissed = false
}

/// 优先展示 Assets.xcassets 中的真实透明底耳机照片（同时支持 iOS 打包与 Mac 预览实时读取），未放入时平滑回退苹果原生符号
struct AppleHeadphoneIcon: View {
    let category: HeadphoneCategory
    var size: CGFloat = 110
    var animated: Bool = false

    @StateObject private var anim = FloatingAnimState()

    var body: some View {
        ZStack {
            if animated {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                GlassTheme.accentBlue.opacity(anim.isFloating ? 0.34 : 0.14),
                                GlassTheme.deepBlue.opacity(anim.isFloating ? 0.14 : 0.04),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: size * 0.08,
                            endRadius: size * 0.95
                        )
                    )
                    .frame(width: size * 1.65, height: size * 1.65)
                    .scaleEffect(anim.isFloating ? 1.06 : 0.94)

                Ellipse()
                    .fill(GlassTheme.accentBlue.opacity(anim.isFloating ? 0.16 : 0.28))
                    .frame(width: size * 0.68, height: size * 0.12)
                    .blur(radius: 8)
                    .offset(y: size * 0.52)
            }

            deviceVisual
                .frame(width: size, height: size)
                .shadow(color: GlassTheme.accentBlue.opacity(animated ? 0.30 : 0.10), radius: 18, x: 0, y: 10)
                .offset(y: animated && anim.isFloating ? -5 : 2)
                .rotation3DEffect(
                    .degrees(animated && anim.isFloating ? 10 : -10),
                    axis: (x: 0.05, y: 1.0, z: 0.0),
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

    #if os(macOS)
    private func loadMacAssetImage(_ name: String) -> NSImage? {
        if let bundled = NSImage(named: name) { return bundled }
        let path = "/Users/cliqueychen/Desktop/作业/健康/EarPulse/EarPulse/Assets.xcassets/\(name).imageset/\(name).png"
        return NSImage(contentsOfFile: path)
    }
    #endif

    @ViewBuilder
    private var deviceVisual: some View {
        #if os(iOS)
        if let assetName = category.localAssetName, UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
        } else {
            fallbackSymbol
        }
        #elseif os(macOS)
        if let assetName = category.localAssetName, let nsImg = loadMacAssetImage(assetName) {
            Image(nsImage: nsImg)
                .resizable()
                .scaledToFit()
        } else {
            fallbackSymbol
        }
        #else
        fallbackSymbol
        #endif
    }

    private var fallbackSymbol: some View {
        Image(systemName: category.sfSymbol)
            .font(.system(size: size * 0.60, weight: .light))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white, GlassTheme.softBlue)
    }
}

// MARK: - 纯黑底 MP4 + Screen 滤色混合播放器（彻底根除 HEVC PremultipliedAlpha 紫边）

enum LaunchAnimationResolver {
    static func videoURL(for category: HeadphoneCategory) -> URL? {
        guard let name = category.launchAnimationName else { return nil }
        let blackName = "\(name)_black"
        if let bundled = Bundle.main.url(forResource: blackName, withExtension: "mp4") {
            return bundled
        }
        if let bundledSub = Bundle.main.url(forResource: blackName, withExtension: "mp4", subdirectory: "LaunchAnimations") {
            return bundledSub
        }
        #if os(macOS)
        let localBlack = "/Users/cliqueychen/Desktop/作业/健康/EarPulse/EarPulse/Resources/LaunchAnimations/\(blackName).mp4"
        if FileManager.default.fileExists(atPath: localBlack) {
            return URL(fileURLWithPath: localBlack)
        }
        #endif
        return nil
    }
}

#if os(iOS)
final class TransparentPlayerUIView: UIView {
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var readyObservation: NSKeyValueObservation?

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    func configure(url: URL) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])

        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = true
        avPlayer.preventsDisplaySleepDuringVideoPlayback = false
        self.player = avPlayer

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak avPlayer] _ in
            avPlayer?.seek(to: .zero)
            avPlayer?.play()
        }

        if let avLayer = layer as? AVPlayerLayer {
            avLayer.opacity = 0.0
            avLayer.player = avPlayer
            avLayer.videoGravity = .resizeAspect
            avLayer.backgroundColor = UIColor.clear.cgColor
            avLayer.isOpaque = false
            avLayer.masksToBounds = true

            readyObservation = avLayer.observe(\.isReadyForDisplay, options: [.new, .initial]) { layer, _ in
                guard layer.isReadyForDisplay else { return }
                DispatchQueue.main.async {
                    CATransaction.begin()
                    CATransaction.setAnimationDuration(0.22)
                    layer.opacity = 1.0
                    CATransaction.commit()
                }
            }
        }
        avPlayer.play()
    }

    func stop() {
        readyObservation?.invalidate()
        readyObservation = nil
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        player?.pause()
        (layer as? AVPlayerLayer)?.player = nil
        player = nil
    }
}

struct TransparentAlphaVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> TransparentPlayerUIView {
        let view = TransparentPlayerUIView()
        view.configure(url: url)
        return view
    }

    func updateUIView(_ uiView: TransparentPlayerUIView, context: Context) {}

    static func dismantleUIView(_ uiView: TransparentPlayerUIView, coordinator: ()) {
        uiView.stop()
    }
}
#elseif os(macOS)
final class TransparentPlayerNSView: NSView {
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var readyObservation: NSKeyValueObservation?
    private let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        // macOS 原生 CoreAnimation Screen 滤色混合，让纯黑底完全透明且零紫边
        layer?.compositingFilter = "screenBlendMode"
        playerLayer.opacity = 0.0
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.isOpaque = false
        playerLayer.masksToBounds = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func configure(url: URL) {
        stop()
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = true
        self.player = avPlayer

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak avPlayer] _ in
            avPlayer?.seek(to: .zero)
            avPlayer?.play()
        }

        playerLayer.opacity = 0.0
        playerLayer.player = avPlayer
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new, .initial]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.22)
                self?.playerLayer.opacity = 1.0
                CATransaction.commit()
            }
        }
        avPlayer.play()
    }

    func stop() {
        readyObservation?.invalidate()
        readyObservation = nil
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        player?.pause()
        playerLayer.player = nil
        player = nil
    }
}

struct TransparentAlphaVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> TransparentPlayerNSView {
        let view = TransparentPlayerNSView()
        view.configure(url: url)
        return view
    }

    func updateNSView(_ nsView: TransparentPlayerNSView, context: Context) {}

    static func dismantleNSView(_ nsView: TransparentPlayerNSView, coordinator: ()) {
        nsView.stop()
    }
}
#endif

/// 四边柔羽化遮罩
private struct SoftVideoEdgeMask: View {
    var body: some View {
        Rectangle()
            .fill(.white)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .white, location: 0.07),
                        .init(color: .white, location: 0.93),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .white, location: 0.07),
                        .init(color: .white, location: 0.93),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

/// 仿 iOS AirPods 开盖底部弹出液态玻璃弹窗（纯黑底 MP4 滤色混合，彻底零紫边）
struct MinimalLaunchOverlay: View {
    let deviceName: String?
    let category: HeadphoneCategory
    let onFinished: () -> Void

    @StateObject private var anim = AirPodsLaunchState()

    private var videoURL: URL? {
        LaunchAnimationResolver.videoURL(for: category)
            ?? LaunchAnimationResolver.videoURL(for: .airPodsPro)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(anim.dismissed ? 0.0 : 0.62)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissNow()
                }

            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button {
                        Haptics.light()
                        dismissNow()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }

                Text(deviceName ?? "earphone useage")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, -10)

                Group {
                    if let url = videoURL, category.launchAnimationName != nil || deviceName == nil {
                        TransparentAlphaVideoView(url: url)
                            .scaleEffect(1.04)
                            .blendMode(.screen)
                            .mask(SoftVideoEdgeMask())
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                    } else {
                        AppleHeadphoneIcon(category: category, size: 146, animated: true)
                            .frame(height: 190)
                    }
                }
                .opacity(anim.visualVisible ? 1.0 : 0.0)

                Text("earphone useage")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(GlassTheme.softBlue.opacity(0.85))
                    .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(22)
            .background {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .fill(Color(red: 0.04, green: 0.06, blue: 0.10).opacity(0.68))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                    )
            }
            .shadow(color: Color.black.opacity(0.60), radius: 28, x: 0, y: 12)
            .padding(.horizontal, 16)
            .padding(.bottom, 22)
            .offset(y: anim.cardUp && !anim.dismissed ? 0 : 440)
            .opacity(anim.dismissed ? 0.0 : 1.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.84)) {
                anim.cardUp = true
            }
            withAnimation(.easeOut(duration: 0.30).delay(0.12)) {
                anim.visualVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                dismissNow()
            }
        }
    }

    private func dismissNow() {
        guard !anim.dismissed else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            anim.dismissed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            onFinished()
        }
    }
}
