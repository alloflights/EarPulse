import AVFAudio
import Combine
import Foundation

/// 实时监听当前连接的耳机设备（蓝牙 / AirPods / 有线）
@MainActor
final class AudioRouteMonitor: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var connectedDeviceName: String = "AirPods Pro (第 2 代)"
    @Published var connectedCategory: HeadphoneCategory = .airPodsPro
    @Published var portTypeDescription: String = "蓝牙音频"
    @Published var isSimulatedSelection: Bool = true

    private var routeChangeObserver: NSObjectProtocol?

    init() {
        refreshCurrentRoute(allowFallback: true)
        startObserving()
    }

    deinit {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func startObserving() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCurrentRoute(allowFallback: false)
            }
        }
    }

    /// 读取 AVAudioSession 当前输出路由中的耳机信息
    func refreshCurrentRoute(allowFallback: Bool = false) {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs

        let headphonePorts: Set<AVAudioSession.Port> = [
            .bluetoothA2DP,
            .bluetoothHFP,
            .bluetoothLE,
            .headphones,
            .headsetMic,
            .usbAudio
        ]

        if let activePort = outputs.first(where: { headphonePorts.contains($0.portType) }) {
            let isWired = activePort.portType == .headphones || activePort.portType == .headsetMic || activePort.portType == .usbAudio
            isConnected = true
            isSimulatedSelection = false
            connectedDeviceName = activePort.portName
            connectedCategory = HeadphoneCategory.infer(from: activePort.portName, isWired: isWired)
            portTypeDescription = isWired ? "有线直连" : "蓝牙无线连接"
        } else if allowFallback {
            // 模拟器或未佩戴耳机时，保持演示耳机用于展示贴图与开启动画
            isConnected = false
            isSimulatedSelection = true
            connectedDeviceName = "AirPods Pro (第 2 代)"
            connectedCategory = .airPodsPro
            portTypeDescription = "演示设备（未检测到真机耳机）"
        } else {
            isConnected = false
            portTypeDescription = "当前未连接耳机"
        }
    }

    /// 供用户在“耳机库”点击切换预览不同耳机的贴图与连接动效
    func selectPreviewHeadphone(name: String, category: HeadphoneCategory) {
        connectedDeviceName = name
        connectedCategory = category
        isSimulatedSelection = true
        portTypeDescription = category == .wired ? "有线预览模式" : "蓝牙预览模式"
    }
}
