import SwiftUI

struct ProxiesView: View {
    @EnvironmentObject var proxyViewModel: ProxyViewModel
    
    var body: some View {
        ZStack {
            Color(hex: "0F172A").ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Bar (if not embedded in NavigationStack, but since we pushed from NavigationView, we can just style navigationTitle or custom bar)
                HStack {
                    Text("Proxies & Groups")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    
                    if proxyViewModel.isTesting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 8)
                    } else {
                        Button(action: {
                            proxyViewModel.testAllLatencies()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                Text("Test All")
                            }
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: "6366F1"))
                            .cornerRadius(14)
                        }
                        .disabled(proxyViewModel.proxies.isEmpty)
                    }
                }
                .padding()
                .background(Color(hex: "1E293B").opacity(0.5))
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        
                        if proxyViewModel.proxies.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "tray")
                                    .font(.system(size: 48))
                                    .foregroundColor(Color(hex: "475569"))
                                Text("No configuration loaded.\nPlease import a Clash YAML file.")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundColor(Color(hex: "64748B"))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 80)
                        } else {
                            
                            // 1. Groups Section
                            if !proxyViewModel.groups.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("PROXY GROUPS")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(hex: "64748B"))
                                        .tracking(1.0)
                                        .padding(.horizontal)
                                    
                                    ForEach(proxyViewModel.groups) { group in
                                        GroupCard(group: group)
                                            .environmentObject(proxyViewModel)
                                    }
                                }
                            }
                            
                            // 2. Individual Proxies Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("INDIVIDUAL SOCKS5 PROXIES")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "64748B"))
                                    .tracking(1.0)
                                    .padding(.horizontal)
                                
                                ForEach(proxyViewModel.proxies) { proxy in
                                    ProxyRow(proxy: proxy)
                                        .environmentObject(proxyViewModel)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Proxy Group Card

struct GroupCard: View {
    let group: ProxyGroup
    @EnvironmentObject var proxyViewModel: ProxyViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group Title & Mode
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(group.type == .select ? "Manual Selection Group" : "Load-Balance Round-Robin Group")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "94A3B8"))
                }
                Spacer()
                
                // Connection selection status
                if proxyViewModel.selectedGroupName == group.name {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "10B981"))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                proxyViewModel.selectGroup(group.name)
            }
            
            // Selector option if Group type is SELECT
            if group.type == .select {
                Divider().background(Color.white.opacity(0.08))
                
                HStack {
                    Text("Active Rule Choice:")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "64748B"))
                    Spacer()
                    
                    Menu {
                        // Options can be proxies or other groups
                        ForEach(group.proxies, id: \.self) { option in
                            Button(action: {
                                proxyViewModel.selectGroupOption(groupName: group.name, optionName: option)
                            }) {
                                HStack {
                                    Text(option)
                                    if (proxyViewModel.groupSelections[group.name] ?? "") == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(proxyViewModel.groupSelections[group.name] ?? "None")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "6366F1"))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "6366F1"))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: "6366F1").opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.03))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(proxyViewModel.selectedGroupName == group.name ? Color(hex: "10B981").opacity(0.5) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// MARK: - Proxy Row Item

struct ProxyRow: View {
    let proxy: SOCKS5Proxy
    @EnvironmentObject var proxyViewModel: ProxyViewModel
    
    var body: some View {
        HStack(spacing: 14) {
            
            // Radio button check
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isSelected ? Color(hex: "10B981") : Color(hex: "475569"))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(proxy.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text("\(proxy.host):\(proxy.port)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "64748B"))
            }
            
            Spacer()
            
            // Latency checker state
            Button(action: {
                proxyViewModel.testLatency(for: proxy)
            }) {
                HStack(spacing: 4) {
                    if status == .checking {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "94A3B8")))
                            .scaleEffect(0.7)
                    } else {
                        // Latency value
                        Text(latencyText)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(latencyColor)
                        
                        // Status dot
                        Circle()
                            .fill(latencyColor)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.03))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
            }
        }
        .padding()
        .background(Color.white.opacity(0.02))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color(hex: "10B981").opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            proxyViewModel.selectProxy(proxy.name)
        }
    }
    
    // MARK: - Helpers
    
    private var isSelected: Bool {
        return proxyViewModel.selectedProxyName == proxy.name && proxyViewModel.selectedGroupName.isEmpty
    }
    
    private var status: ProxyStatus {
        return proxyViewModel.statuses[proxy.id] ?? .unknown
    }
    
    private var latencyText: String {
        if status == .checking { return "" }
        if let latency = proxyViewModel.latencies[proxy.id] {
            return "\(latency) ms"
        }
        switch status {
        case .unknown: return "Check"
        case .authFailed: return "Auth Error"
        case .connFailed: return "Dead"
        case .timeout: return "Timeout"
        default: return "Offline"
        }
    }
    
    private var latencyColor: Color {
        switch status {
        case .online:
            return Color(hex: "10B981") // Green
        case .slow:
            return Color(hex: "F59E0B") // Amber
        case .authFailed, .connFailed, .timeout:
            return Color(hex: "EF4444") // Red
        default:
            return Color(hex: "64748B") // Gray
        }
    }
}
