import SwiftUI

@main
struct TunnexaApp: App {
    @StateObject private var proxyViewModel = ProxyViewModel()
    @AppStorage("setting_appearance") private var appearance: String = "System"
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                MainView()
                    .tabItem {
                        Label("Dashboard", systemImage: "bolt.shield")
                    }

                ProxiesView()
                    .tabItem {
                        Label("Proxies", systemImage: "network")
                    }

                DiagnosticsView()
                    .tabItem {
                        Label("Diagnostics", systemImage: "terminal")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
            }
            .environmentObject(proxyViewModel)
            .preferredColorScheme(colorScheme)
            .accentColor(Color(hex: "6366F1"))
            .onOpenURL { url in
                proxyViewModel.importYAML(from: url)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Refresh stored config and attempt auto-connect when configured.
                proxyViewModel.loadSavedConfig()
                let caps = VPNEnvironmentDetector.currentCapabilities()
                if caps.canUsePacketTunnel {
                    VPNManager.shared.autoConnectIfNeeded()
                } else if caps.canUseInAppProxy, SharedSettings().inAppProxyEnabled {
                    InAppProxyManager.shared.start()
                }
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "Light":
            return .light
        case "Dark":
            return .dark
        default:
            return nil
        }
    }
}