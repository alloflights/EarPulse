# EarPulse（聆听护盾）— iOS SwiftUI 耳机分贝与听觉健康 App

采用苹果原生「健康」清新极简风格，基于 **SwiftUI + Swift Charts + HealthKit + AVFAudio** 构建（支持 iOS 17+）。

## 核心功能

1. **Apple HealthKit 耳机分贝接入**：
   - 读取 [`headphoneAudioExposure`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/headphoneaudioexposure)（单位 dBASPL）与 [`headphoneAudioExposureEvent`](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/headphoneaudioexposureevent) 高音量通知事件。
   - 内置**演示模式 / 真实健康数据一键切换**：在模拟器或真机暂无数据时自动展示多耳机 7 天示例数据，真机授权后无缝同步真实记录。
2. **多耳机自动区分与对比**：
   - 结合 HealthKit `HKDevice` 元数据与 `AVAudioSession.currentRoute` 实时音频路由，自动识别并归类不同耳机（AirPods Pro、AirPods Max、AirPods、头戴式蓝牙耳机、有线 EarPods）。
   - 横向对比各副耳机的平均分贝、峰值分贝、累计时长与护耳评分。
3. **当前耳机 3D 贴图与开启动画**：
   - 内置 5 款高精度 SwiftUI 3D 质感耳机贴图，支持悬浮微旋与分贝色系声波涟漪。
   - App 启动时播放当前耳机的弹性入场与声波开场动画（首页右上角 ✨ 可随时重播）；在「我的耳机」页点击任意设备可弹出仿 AirPods 风格的 3D 预览弹窗并切换首页展示。
4. **新增创意护耳功能**：
   - **WHO 每日听力安全额度环**：按 3 dB 交换率动态换算今日剩余安全聆听额度与当前音量建议时长上限。
   - **多耳机护耳洞察**：自动比较不同耳机的平均分贝差异并给出降噪/音量习惯建议。
   - **60-60 听觉护耳番茄钟**：支持 25m / 45m / 60m 聆听倒计时与 5m 摘机休息模式。
   - **交互式分贝安全模拟尺**：拖动滑块即时查看 45–105 dB 对应的生活场景与每日安全时长。
   - **本周听觉健康周报分享卡**：自动生成 S/A/B/C 评级报告，支持通过 `ImageRenderer` 一键导出分享。

## 在 Xcode 中运行步骤

1. 双击打开 `EarPulse.xcodeproj`。
2. 在左侧点击 `EarPulse` 工程 → `Signing & Capabilities` → 选择你的 Apple ID / Team（真机运行需要勾选 **HealthKit** 能力，已在 `EarPulse.entitlements` 中预设）。
3. 选择 iPhone 真机或 iOS 17+ 模拟器，按 `Cmd + R` 运行。
4. 若在真机测试真实数据，打开 App 后点击首页顶部「同步健康」按钮并允许读取「耳机音频音量」与「耳机通知」即可。
