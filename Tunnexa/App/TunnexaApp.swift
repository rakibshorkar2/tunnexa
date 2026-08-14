import SwiftUI

@main
struct TunnexaApp: App {
    @StateObject private var proxyViewModel = ProxyViewModel()
    @AppStorage("setting_appearance") private var appearance: String = "System"
    
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
                // Support opening YAML configs via Share Sheet/AirDrop/Files app
                proxyViewModel.importYAML(from: url)
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
