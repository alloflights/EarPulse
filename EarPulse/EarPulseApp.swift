import Combine
import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
private final class LaunchState: ObservableObject {
    @Published var showLaunchOverlay = true
}

@main
struct EarPulseApp: App {
    @StateObject private var dataStore = HealthDataStore()
    @StateObject private var audioMonitor = AudioRouteMonitor()
    @StateObject private var lang = LanguageStore()
    @StateObject private var limitMonitor = UsageLimitMonitor()
    @StateObject private var launchState = LaunchState()

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(dataStore)
                    .environmentObject(audioMonitor)
                    .environmentObject(lang)
                    .environmentObject(limitMonitor)
                    .preferredColorScheme(.dark)
                    .task {
                        limitMonitor.bind(audioMonitor: audioMonitor, dataStore: dataStore)
                        await dataStore.bootstrapOnLaunch()
                    }

                if launchState.showLaunchOverlay {
                    MinimalLaunchOverlay(
                        deviceName: audioMonitor.connectedDeviceName,
                        category: audioMonitor.connectedCategory
                    ) {
                        launchState.showLaunchOverlay = false
                    }
                    .zIndex(1)
                }
            }
            #if os(macOS)
            .frame(width: 393, height: 852)
            .onAppear {
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        #endif
    }
}
