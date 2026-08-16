import SwiftUI
import NetworkExtension

struct MainView: View {
    @EnvironmentObject var proxyViewModel: ProxyViewModel
    @StateObject var vpnViewModel = VPNViewModel()
    @ObservedObject private var inAppProxy = InAppProxyManager.shared
    @State private var isImporting = false
    @State private var showImportAlert = false

    private let environment = VPNEnvironmentDetector.detectEnvironment()
    private let capabilities = VPNEnvironmentDetector.currentCapabilities()

    var body: some View {
        NavigationStack {
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
                                Text(subtitle)
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
                        
                        if capabilities.canUsePacketTunnel {
                            systemVPNContent
                        } else if capabilities.canUseInAppProxy {
                            inAppProxyContent
                        } else {
                            unsupportedEnvironmentContent
                        }
                        
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
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isImporting) {
                ImportConfigSheet()
                    .environmentObject(proxyViewModel)
            }
            .alert(
                vpnViewModel.activeError?.environment.isSupportedForSystemVPN == false ? "Unsupported Environment" : "VPN Connection Alert",
                isPresented: Binding(
                    get: { vpnViewModel.activeError != nil },
                    set: { if !$0 { vpnViewModel.activeError = nil } }
                )
            ) {
                Button("OK") { vpnViewModel.activeError = nil }
            } message: {
                Text(vpnViewModel.activeError?.userFriendlyExplanation ?? "")
            }
        }
    }
    
    // MARK: - Environment Mode Content
    
    private var subtitle: String {
        if capabilities.canUsePacketTunnel {
            return "System-wide SOCKS5 VPN"
        }
        if capabilities.canUseInAppProxy {
            return "In-App SOCKS5 Proxy"
        }
        return "Unsupported Environment"
    }

    /// Mode A: the real system-wide packet tunnel.
    private var systemVPNContent: some View {
        VStack(spacing: 28) {
            // Status Card (Connected / Disconnected)
            VStack(spacing: 6) {
                Text(vpnViewModel.state == .connected ? "CONNECTED" : (vpnViewModel.state.isActive ? statusLabel.uppercased() : "DISCONNECTED"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundColor(statusColor)

                if vpnViewModel.state.isConnected {
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
                        .scaleEffect(vpnViewModel.state.isConnected ? 1.05 : 1.0)
                        .blur(radius: vpnViewModel.state.isConnected ? 4 : 0)
                        .animation(vpnViewModel.state.isConnected ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .default, value: vpnViewModel.state.isConnected)
                    
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
                        .shadow(color: statusColor.opacity(0.4), radius: vpnViewModel.state.isConnected ? 20 : 5)
                    
                    // Icon / Label
                    VStack(spacing: 8) {
                        Image(systemName: "power")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(statusColor)
                        if vpnViewModel.isBusy {
                            ProgressView()
                                .tint(.white)
                                .padding(.top, 2)
                        } else {
                            Text(vpnViewModel.state.isConnected ? "DISCONNECT" : "CONNECT")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
            }
            .disabled(vpnViewModel.state.isActive)
            .padding(.vertical, 16)
        }
    }

    /// Mode C: honest in-app loopback proxy (LiveContainer guest, simulator).
    /// Never presents this as a system VPN and never touches the VPN profile.
    private var inAppProxyContent: some View {
        VStack(spacing: 20) {
            // Status Card
            VStack(spacing: 6) {
                Text(inAppProxy.isRunning ? "PROXY RUNNING" : "PROXY STOPPED")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundColor(inAppProxy.isRunning ? Color(hex: "10B981") : Color(hex: "64748B"))

                Text("127.0.0.1:\(AppConfigConstants.localProxyPort)")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }

            // Start / Stop
            Button(action: {
                if inAppProxy.isRunning {
                    inAppProxy.stop()
                } else {
                    inAppProxy.start()
                }
            }) {
                Text(inAppProxy.isRunning ? "STOP PROXY" : "START PROXY")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: inAppProxy.isRunning
                                ? [Color(hex: "B91C1C"), Color(hex: "991B1B")]
                                : [Color(hex: "6366F1"), Color(hex: "4F46E5")]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)

            if let error = inAppProxy.lastError {
                Text(error)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "F87171"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if SharedSettings().localAuthEnabled {
                Text("Local authentication is enabled — guest apps must send the configured username and password (RFC 1929).")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "F59E0B"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Text("This is a LOCAL proxy, not a system VPN. Configure guest applications to use SOCKS5 at 127.0.0.1:\(AppConfigConstants.localProxyPort). Only traffic from those applications is proxied — the rest of the system is unaffected.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "94A3B8"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 16)
    }

    /// Runtimes that support neither mode: honest refusal, no controls.
    private var unsupportedEnvironmentContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(Color(hex: "F59E0B"))
            Text("Unsupported Environment")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Tunnexa could not positively identify this installation as a standalone app, a LiveContainer guest, or the simulator. It will not attempt to start a VPN in an ambiguous runtime. Reinstall Tunnexa as a standalone app and try again.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "94A3B8"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 24)
    }

    // MARK: - Computed Properties
    
    private var statusColor: Color {
        switch vpnViewModel.state {
        case .connected:
            return Color(hex: "10B981") // Green
        case .connecting, .preparing:
            return Color(hex: "F59E0B") // Amber
        case .reasserting:
            return Color(hex: "F59E0B") // Amber
        case .failed, .invalid:
            return Color(hex: "F43F5E") // Red
        default:
            return Color(hex: "64748B") // Slate/Gray
        }
    }

    private var statusLabel: String {
        switch vpnViewModel.state {
        case .preparing: return "Preparing..."
        case .connecting: return "Connecting..."
        case .reasserting: return "Reconnecting..."
        case .disconnecting: return "Disconnecting..."
        case .failed: return "Failed"
        case .invalid: return "Invalid Profile"
        default: return "Disconnected"
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
