import SwiftUI

@main
struct EarPulseApp: App {
    @StateObject private var healthManager = HealthKitManager()
    @StateObject private var audioMonitor = AudioRouteMonitor()
    @State private var showLaunchAnimation = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(onReplayLaunch: {
                    showLaunchAnimation = true
                })
                .environmentObject(healthManager)
                .environmentObject(audioMonitor)

                if showLaunchAnimation {
                    LaunchAnimationView(
                        deviceName: audioMonitor.connectedDeviceName,
                        category: audioMonitor.connectedCategory
                    ) {
                        showLaunchAnimation = false
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
        }
    }
}
