import SwiftUI

/// 主导航容器（5 标签栏：概览 / 统计 / 耳机 / 护耳 / 周报）
struct ContentView: View {
    @EnvironmentObject private var healthManager: HealthKitManager
    @EnvironmentObject private var audioMonitor: AudioRouteMonitor

    var onReplayLaunch: () -> Void
    @State private var selectedTab: Int = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(onReplayLaunch: onReplayLaunch)
                .tabItem {
                    Label("概览", systemImage: "heart.text.square.fill")
                }
                .tag(0)

            UsageStatsView()
                .tabItem {
                    Label("统计", systemImage: "chart.bar.xaxis")
                }
                .tag(1)

            DevicesView(onSelectDevicePreview: {
                selectedTab = 0
            })
            .tabItem {
                Label("耳机", systemImage: "headphones")
            }
            .tag(2)

            ProtectionToolsView()
                .tabItem {
                    Label("护耳", systemImage: "ear.badge.checkmark")
                }
                .tag(3)

            WeeklyReportView()
                .tabItem {
                    Label("周报", systemImage: "doc.richtext.fill")
                }
                .tag(4)
        }
        .tint(audioMonitor.connectedCategory.accentColor)
    }
}
