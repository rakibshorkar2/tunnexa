import SwiftUI

struct DiagnosticsView: View {
    @StateObject var vpnViewModel = VPNViewModel()
    @State private var logsText: String = ""
    @State private var isCopied = false
    
    private let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    private let sharedDefaults = UserDefaults(suiteName: "group.com.rakib.tunnexa")!
    
    var body: some View {
        ZStack {
            Color(hex: "0F172A").ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Diagnostics")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding()
                .background(Color(hex: "1E293B").opacity(0.5))
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        
                        // 1. Connection Parameters Card
                        VStack(alignment: .leading, spacing: 14) {
                            Text("TUNNEL PARAMETERS")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "64748B"))
                                .tracking(1.0)
                            
                            DiagnosticItemRow(title: "Tunnel Status", value: statusString, color: statusColor)
                            DiagnosticItemRow(title: "IPv4 Interface", value: "198.18.0.1")
                            DiagnosticItemRow(title: "IPv6 Interface", value: sharedDefaults.bool(forKey: "setting_ipv6") ? "fc00::1" : "Disabled")
                            DiagnosticItemRow(title: "Local DNS Address", value: "198.18.0.2")
                            DiagnosticItemRow(title: "Interface MTU Size", value: String(sharedDefaults.integer(forKey: "setting_mtu") != 0 ? sharedDefaults.integer(forKey: "setting_mtu") : 9000))
                            DiagnosticItemRow(title: "Packets Sent (Bytes)", value: vpnViewModel.bytesSent)
                            DiagnosticItemRow(title: "Packets Received (Bytes)", value: vpnViewModel.bytesReceived)
                        }
                        .padding()
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        
                        // 2. Logs Terminal Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("SYSTEM LOGS")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "64748B"))
                                    .tracking(1.0)
                                Spacer()
                                
                                // Copy Button
                                Button(action: copyToClipboard) {
                                    HStack(spacing: 4) {
                                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                        Text(isCopied ? "Copied" : "Copy")
                                    }
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(isCopied ? Color(hex: "10B981") : Color(hex: "6366F1"))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(isCopied ? Color(hex: "10B981").opacity(0.1) : Color(hex: "6366F1").opacity(0.1))
                                    .cornerRadius(8)
                                }
                                
                                // Clear Button
                                Button(action: clearLogs) {
                                    Text("Clear")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(hex: "EF4444"))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color(hex: "EF4444").opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                            
                            // Log lines display box
                            ScrollView {
                                Text(logsText.isEmpty ? "No log output available." : logsText)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.75))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                                    .padding(10)
                            }
                            .frame(height: 260)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                            )
                        }
                        .padding()
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
        }
        .onAppear(perform: refreshLogs)
        .onReceive(timer) { _ in
            refreshLogs()
        }
    }
    
    // MARK: - Logic
    
    private func refreshLogs() {
        logsText = SharedLogging.readLogs()
    }
    
    private func clearLogs() {
        SharedLogging.clearLogs()
        refreshLogs()
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = logsText
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isCopied = false
        }
    }
    
    private var statusString: String {
        switch vpnViewModel.status {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .reasserting: return "Reasserting..."
        case .disconnecting: return "Disconnecting..."
        default: return "Disconnected"
        }
    }
    
    private var statusColor: Color {
        switch vpnViewModel.status {
        case .connected: return Color(hex: "10B981")
        case .connecting, .reasserting: return Color(hex: "F59E0B")
        default: return Color(hex: "EF4444")
        }
    }
}

struct DiagnosticItemRow: View {
    let title: String
    let value: String
    var color: Color = .white
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "94A3B8"))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(color)
        }
    }
}
