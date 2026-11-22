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

/// 真正 iOS 26/27 原生 Liquid Glass 悬浮双入口主容器
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

                ZStack {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }

            floatingLiquidTabBar
                .padding(.bottom, 14)
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

    // MARK: - 顶部极简栏
    private var topBar: some View {
        HStack(spacing: 10) {
            Text("earphone useage")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            topGlassButtons
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var topGlassButtons: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    languageButton
                        .glassEffect(.regular.interactive(), in: .capsule)
                    syncMenuButton
                        .glassEffect(.regular.interactive(), in: .circle)
                }
            }
        } else {
            HStack(spacing: 10) {
                languageButton
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(GlassTheme.glassRimGradient, lineWidth: 1))
                syncMenuButton
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(GlassTheme.glassRimGradient, lineWidth: 1))
            }
        }
    }

    private var languageButton: some View {
        Button {
            Haptics.soft()
            withAnimation(.snappy(duration: 0.25)) {
                lang.toggle()
            }
        } label: {
            Text(lang.isEnglish ? "中文" : "EN")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 44, height: 36)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var syncMenuButton: some View {
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
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: 36, height: 36)
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - 首次接入页
    private var emptyRealDataView: some View {
        VStack(spacing: 28) {
            Spacer()

            AppleHeadphoneIcon(
                category: audioMonitor.connectedCategory,
                size: 100,
                animated: true
            )
            .frame(height: 132)

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

    // MARK: - 真正 iOS 26/27 原生 Liquid Glass 悬浮底栏（外框 .regular 不拦截点击，子按钮精准切换）
    @ViewBuilder
    private var floatingLiquidTabBar: some View {
        let tabs = HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                let isSelected = uiState.selectedTab == tab
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.80)) {
                        uiState.selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.icon)
                            .font(.subheadline.weight(.semibold))
                        Text(tab == .stats ? lang.statsTab : lang.devicesTab)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .contentShape(Capsule())
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(GlassTheme.activeBlueGlass)
                                .shadow(color: GlassTheme.accentBlue.opacity(0.45), radius: 12, x: 0, y: 4)
                                .matchedGeometryEffect(id: "ACTIVE_TAB_PILL", in: tabNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)

        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                tabs
                    .glassEffect(.regular, in: .capsule)
            }
        } else {
            tabs
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(GlassTheme.glassRimGradient, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.65), radius: 22, x: 0, y: 12)
                }
        }
    }
}
