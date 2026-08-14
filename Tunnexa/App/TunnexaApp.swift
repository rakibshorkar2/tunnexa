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

// MARK: - Color Hex Extension
extension Color {
    /// Initialise a Color from a 6-digit RGB hex string, e.g. "6366F1"
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (1, 1, 0) // fallback: yellow signals misconfiguration
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
