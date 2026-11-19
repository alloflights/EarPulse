import Combine
import Foundation
#if os(iOS)
import AVFAudio
#endif

/// 实时监听当前真实连接的蓝牙 / 有线耳机（iOS 真机实时检测，macOS 预览兼容）
@MainActor
final class AudioRouteMonitor: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var connectedDeviceName: String?
    @Published var connectedCategory: HeadphoneCategory = .airPodsPro
    @Published var connectionTypeLabel: String = ""

    private var routeChangeObserver: NSObjectProtocol?

    init() {
        refreshCurrentRoute()
        startObserving()
    }

    deinit {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func startObserving() {
        #if os(iOS)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCurrentRoute()
            }
        }
        #endif
    }

    func refreshCurrentRoute() {
        #if os(iOS)
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let headphonePorts: Set<AVAudioSession.Port> = [
            .bluetoothA2DP, .bluetoothHFP, .bluetoothLE,
            .headphones, .headsetMic, .usbAudio
        ]

        if let active = outputs.first(where: { headphonePorts.contains($0.portType) }) {
            let isWired = active.portType == .headphones || active.portType == .headsetMic || active.portType == .usbAudio
            isConnected = true
            connectedDeviceName = active.portName
            connectedCategory = HeadphoneCategory.infer(from: active.portName, isWired: isWired)
            connectionTypeLabel = isWired ? "有线已连接" : "蓝牙已连接"
        } else {
            isConnected = false
            connectedDeviceName = nil
            connectionTypeLabel = ""
        }
        #else
        isConnected = false
        connectedDeviceName = nil
        connectionTypeLabel = ""
        #endif
    }
}
