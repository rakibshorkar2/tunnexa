import SwiftUI
import NetworkExtension

struct MainView: View {
    @EnvironmentObject var proxyViewModel: ProxyViewModel
    @StateObject var vpnViewModel = VPNViewModel()
    @State private var isImporting = false
    @State private var showImportAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background Gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "0F172A"), Color(hex: "1E293B")]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        
                        // Header
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tunnexa")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("System-wide SOCKS5 VPN")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(Color(hex: "94A3B8"))
                            }
                            Spacer()
                            
                            // Quick Import Button
                            Button(action: {
                                isImporting = true
                            }) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                        
                        // Status Card (Connected / Disconnected)
                        VStack(spacing: 6) {
                            Text(vpnViewModel.status == .connected ? "CONNECTED" : (vpnViewModel.status == .connecting ? "CONNECTING..." : "DISCONNECTED"))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .tracking(2.0)
                                .foregroundColor(statusColor)
                            
                            if vpnViewModel.status == .connected {
                                Text(vpnViewModel.sessionDuration)
                                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        
                        // Glowing Connect Button
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                vpnViewModel.toggleConnection()
                            }
                        }) {
                            ZStack {
                                // Outer Glow Ring
                                Circle()
                                    .stroke(statusColor.opacity(0.3), lineWidth: 10)
                                    .frame(width: 190, height: 190)
                                    .scaleEffect(vpnViewModel.status == .connected ? 1.05 : 1.0)
                                    .blur(radius: vpnViewModel.status == .connected ? 4 : 0)
                                    .animation(vpnViewModel.status == .connected ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .default, value: vpnViewModel.status)
                                
                                // Inner Ring
                                Circle()
                                    .stroke(statusColor, lineWidth: 4)
                                    .frame(width: 165, height: 165)
                                
                                // Button Body
                                Circle()
                                    .fill(LinearGradient(
                                        gradient: Gradient(colors: [Color(hex: "1E293B"), Color(hex: "0F172A")]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .frame(width: 150, height: 150)
                                    .shadow(color: statusColor.opacity(0.4), radius: vpnViewModel.status == .connected ? 20 : 5)
                                
                                // Icon / Label
                                VStack(spacing: 8) {
                                    Image(systemName: "power")
                                        .font(.system(size: 44, weight: .bold))
                                        .foregroundColor(statusColor)
                                    Text(vpnViewModel.status == .connected ? "DISCONNECT" : "CONNECT")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                            }
                        }
                        .disabled(vpnViewModel.status == .connecting || vpnViewModel.status == .disconnecting)
                        .padding(.vertical, 16)
                        
                        // Latency & Speeds Grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            
                            // Latency
                            MetricCard(
                                title: "LATENCY",
                                value: activeProxyLatency,
                                icon: "gauge.medium",
                                iconColor: Color(hex: "38BDF8")
                            )
                            
                            // Session Data (Total Transfer)
                            MetricCard(
                                title: "UPLOAD SPEED",
                                value: vpnViewModel.uploadSpeed,
                                icon: "arrow.up.circle",
                                iconColor: Color(hex: "F43F5E")
                            )
                            
                            MetricCard(
                                title: "DOWNLOAD SPEED",
                                value: vpnViewModel.downloadSpeed,
                                icon: "arrow.down.circle",
                                iconColor: Color(hex: "10B981")
                            )
                            
                            MetricCard(
                                title: "TOTAL DATA",
                                value: totalDataTransferred,
                                icon: "chart.bar.xaxis",
                                iconColor: Color(hex: "A855F7")
                            )
                        }
                        .padding(.horizontal)
                        
                        // Active Proxy Details Card
                        VStack(alignment: .leading, spacing: 14) {
                            Text("ACTIVE PROXY")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "94A3B8"))
                                .tracking(1.0)
                            
                            HStack(spacing: 16) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.05))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "network")
                                        .font(.system(size: 22))
                                        .foregroundColor(statusColor)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(activeProxyName)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text(activeProxyEndpoint)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(Color(hex: "64748B"))
                                }
                                Spacer()
                                
                                NavigationLink(destination: ProxiesView()) {
                                    Text("Change")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color(hex: "6366F1"))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color(hex: "6366F1").opacity(0.1))
                                        .cornerRadius(18)
                                }
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let firstUrl = urls.first {
                        proxyViewModel.importYAML(from: firstUrl)
                        showImportAlert = true
                    }
                case .failure(let error):
                    SharedLogging.log("File Picker failure: \(error.localizedDescription)", category: .yaml)
                }
            }
            .alert(isPresented: $showImportAlert) {
                Alert(
                    title: Text("YAML Configuration"),
                    message: Text(proxyViewModel.importStatusMessage ?? "No status message"),
                    dismissButton: .default(Text("OK")) {
                        proxyViewModel.importStatusMessage = nil
                    }
                )
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusColor: Color {
        switch vpnViewModel.status {
        case .connected:
            return Color(hex: "10B981") // Green
        case .connecting:
            return Color(hex: "F59E0B") // Amber
        default:
            return Color(hex: "64748B") // Slate/Gray
        }
    }
    
    private var activeProxyName: String {
        if !proxyViewModel.selectedGroupName.isEmpty {
            return proxyViewModel.selectedGroupName
        }
        return proxyViewModel.selectedProxyName.isEmpty ? "Direct Route" : proxyViewModel.selectedProxyName
    }
    
    private var activeProxyEndpoint: String {
        if !proxyViewModel.selectedGroupName.isEmpty {
            return "Load Balance Group"
        }
        if let proxy = proxyViewModel.proxies.first(where: { $0.name == proxyViewModel.selectedProxyName }) {
            return "\(proxy.host):\(proxy.port)"
        }
        return "Local Device Network Stack"
    }
    
    private var activeProxyLatency: String {
        if !proxyViewModel.selectedGroupName.isEmpty {
            return "Auto"
        }
        if let proxy = proxyViewModel.proxies.first(where: { $0.name == proxyViewModel.selectedProxyName }),
           let latency = proxyViewModel.latencies[proxy.id] {
            return "\(latency) ms"
        }
        return "—"
    }
    
    private var totalDataTransferred: String {
        return vpnViewModel.bytesReceived // In general, download matches the core data
    }
}

// MARK: - Subviews

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
                Spacer()
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "64748B"))
                    .tracking(1.0)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.white.opacity(0.03))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 1)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
