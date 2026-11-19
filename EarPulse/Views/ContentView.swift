import Combine
import SwiftUI
import UniformTypeIdentifiers

enum AppTab: Int, CaseIterable {
    case stats = 0
    case devices = 1

    var icon: String {
        switch self {
        case .stats: return "chart.bar.fill"
        case .devices: return "airpodspro"
        }
    }
}

@MainActor
private final class ContentViewState: ObservableObject {
    @Published var selectedTab: AppTab = .stats
    @Published var showXMLImporter = false
}

/// 极简液态玻璃双入口主容器（零说明性文字 + 底部栏常驻 + 精细震动反馈）
struct ContentView: View {
    @EnvironmentObject private var dataStore: HealthDataStore
    @EnvironmentObject private var audioMonitor: AudioRouteMonitor
    @EnvironmentObject private var lang: LanguageStore

    @StateObject private var uiState = ContentViewState()
    @Namespace private var tabNamespace

    var body: some View {
        ZStack(alignment: .bottom) {
            LiquidGlassBackdrop()

            VStack(spacing: 0) {
                topBar

                Group {
                    switch uiState.selectedTab {
                    case .stats:
                        if dataStore.hasRealData {
                            StatsView()
                        } else {
                            emptyRealDataView
                        }
                    case .devices:
                        DevicesView()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            floatingLiquidTabBar
                .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: uiState.selectedTab)
        .fileImporter(
            isPresented: $uiState.showXMLImporter,
            allowedContentTypes: [.xml],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    await dataStore.importHealthExportXML(from: url)
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("earphone useage")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Button {
                Haptics.soft()
                withAnimation(.snappy(duration: 0.25)) {
                    lang.toggle()
                }
            } label: {
                Text(lang.isEnglish ? "中文" : "EN")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 42, height: 36)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(GlassTheme.glassRimGradient, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    Haptics.medium()
                    Task { await dataStore.connectAppleHealth() }
                } label: {
                    Label(lang.syncHealth, systemImage: "heart.fill")
                }

                Button {
                    Haptics.light()
                    uiState.showXMLImporter = true
                } label: {
                    Label(lang.importXML, systemImage: "doc.badge.plus")
                }
            } label: {
                ZStack {
                    if dataStore.isLoading {
                        ProgressView()
                            .tint(GlassTheme.accentBlue)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(GlassTheme.glassRimGradient, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var emptyRealDataView: some View {
        VStack(spacing: 28) {
            Spacer()

            AppleHeadphoneIcon(
                category: audioMonitor.connectedCategory,
                size: 88,
                animated: true
            )
            .frame(height: 120)

            VStack(spacing: 12) {
                Button {
                    Haptics.medium()
                    Task { await dataStore.connectAppleHealth() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                        Text(lang.appleHealth)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(LiquidGlassPillButtonStyle(prominent: true))

                Button {
                    Haptics.light()
                    uiState.showXMLImporter = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                        Text(lang.importXML)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(LiquidGlassPillButtonStyle(prominent: false))
            }
            .padding(.horizontal, 36)

            if let error = dataStore.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(GlassTheme.softBlue)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer().frame(height: 60)
        }
    }

    private var floatingLiquidTabBar: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                let isSelected = uiState.selectedTab == tab
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                        uiState.selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.icon)
                            .font(.subheadline.weight(.semibold))
                        Text(tab == .stats ? lang.statsTab : lang.devicesTab)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.52))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(GlassTheme.activeBlueGlass)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                                )
                                .shadow(color: GlassTheme.accentBlue.opacity(0.35), radius: 12, x: 0, y: 4)
                                .matchedGeometryEffect(id: "ACTIVE_TAB_PILL", in: tabNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.05)))
                .overlay(Capsule().strokeBorder(GlassTheme.glassRimGradient, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.65), radius: 22, x: 0, y: 12)
        }
    }
}
