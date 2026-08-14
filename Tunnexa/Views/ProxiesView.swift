import SwiftUI

struct ProxiesView: View {
    @EnvironmentObject var proxyViewModel: ProxyViewModel
    
    @State private var isAddProxyPresented = false
    @State private var isImportPresented = false
    @State private var editingProxy: SOCKS5Proxy? = nil
    
    var body: some View {
        ZStack {
            Color(hex: "0F172A").ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Custom Navigation Bar
                HStack(spacing: 12) {
                    Text("Proxies & Groups")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Import Button
                    Button(action: {
                        isImportPresented = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import")
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Add Proxy Button
                    Button(action: {
                        editingProxy = nil
                        isAddProxyPresented = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add")
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "10B981"))
                        .cornerRadius(12)
                    }
                    
                    // Test All Button
                    if proxyViewModel.isTesting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                            Text("\(proxyViewModel.testedCount)/\(proxyViewModel.proxies.count)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            Button(action: {
                                proxyViewModel.cancelLatencyTests()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color(hex: "F43F5E"))
                            }
                        }
                        .padding(.leading, 4)
                    } else {
                        Button(action: {
                            proxyViewModel.testAllLatencies()
                        }) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color(hex: "6366F1"))
                                .clipShape(Circle())
                        }
                        .disabled(proxyViewModel.proxies.isEmpty)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(hex: "1E293B").opacity(0.5))
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        if !proxyViewModel.proxies.isEmpty {
                            // Search & sort
                            HStack(spacing: 10) {
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 13))
                                        .foregroundColor(Color(hex: "64748B"))
                                    TextField("Search proxies", text: $proxyViewModel.searchText)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(10)

                                Menu {
                                    Picker("Sort", selection: $proxyViewModel.sortOrder) {
                                        Text("Name").tag(ProxySortOrder.name)
                                        Text("Latency").tag(ProxySortOrder.latency)
                                    }
                                } label: {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal)
                        }

                        if proxyViewModel.proxies.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "tray.and.arrow.down")
                                    .font(.system(size: 52))
                                    .foregroundColor(Color(hex: "475569"))
                                
                                Text("No Proxies Configured")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("Add a SOCKS5 proxy manually or paste/import a Clash YAML configuration.")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(Color(hex: "94A3B8"))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                
                                HStack(spacing: 14) {
                                    Button(action: {
                                        editingProxy = nil
                                        isAddProxyPresented = true
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "plus.circle.fill")
                                            Text("Add SOCKS5 Proxy")
                                        }
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Color(hex: "10B981"))
                                        .cornerRadius(12)
                                    }
                                    
                                    Button(action: {
                                        isImportPresented = true
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "doc.text")
                                            Text("Import YAML")
                                        }
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Color(hex: "6366F1"))
                                        .cornerRadius(12)
                                    }
                                }
                                .padding(.top, 8)
                            }
                            .padding(.vertical, 60)
                        } else {
                            
                            // 1. Groups Section
                            if !proxyViewModel.groups.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("PROXY GROUPS")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
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
                                HStack {
                                    Text("INDIVIDUAL SOCKS5 PROXIES (\(proxyViewModel.proxies.count))")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(hex: "64748B"))
                                        .tracking(1.0)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                
                                ForEach(proxyViewModel.filteredProxies) { proxy in
                                    ProxyRow(
                                        proxy: proxy,
                                        onEdit: {
                                            editingProxy = proxy
                                            isAddProxyPresented = true
                                        },
                                        onDelete: {
                                            withAnimation {
                                                proxyViewModel.deleteProxy(id: proxy.id)
                                            }
                                        }
                                    )
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
        .sheet(isPresented: $isAddProxyPresented) {
            AddProxySheet(editingProxy: editingProxy)
                .environmentObject(proxyViewModel)
        }
        .sheet(isPresented: $isImportPresented) {
            ImportConfigSheet()
                .environmentObject(proxyViewModel)
        }
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
                        .font(.system(size: 16, weight: .bold, design: .rounded))
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
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "6366F1"))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "6366F1"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "6366F1").opacity(0.1))
                        .cornerRadius(10)
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
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    
    @EnvironmentObject var proxyViewModel: ProxyViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            
            // Radio button check
            Button(action: {
                proxyViewModel.selectProxy(proxy.name)
            }) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? Color(hex: "10B981") : Color(hex: "475569"))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(proxy.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text("\(proxy.host):\(proxy.port)\(proxy.username != nil ? " (Auth)" : "")")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "64748B"))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                proxyViewModel.selectProxy(proxy.name)
            }
            
            Spacer()
            
            // Edit Button
            if let onEdit = onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "94A3B8"))
                        .padding(6)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
            }
            
            // Delete Button
            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "EF4444").opacity(0.8))
                        .padding(6)
                        .background(Color(hex: "EF4444").opacity(0.1))
                        .clipShape(Circle())
                }
            }
            
            // Latency checker state
            Button(action: {
                proxyViewModel.testLatency(for: proxy)
            }) {
                HStack(spacing: 4) {
                    if status == .checking {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "94A3B8")))
                            .scaleEffect(0.6)
                    } else {
                        Text(latencyText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(latencyColor)
                        
                        Circle()
                            .fill(latencyColor)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.03))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color(hex: "10B981").opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal)
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
        case .authFailed: return "Auth Err"
        case .connFailed: return "Dead"
        case .timeout: return "Timeout"
        default: return "Offline"
        }
    }
    
    private var latencyColor: Color {
        switch status {
        case .online:
            return Color(hex: "10B981")
        case .slow:
            return Color(hex: "F59E0B")
        case .authFailed, .connFailed, .timeout:
            return Color(hex: "EF4444")
        default:
            return Color(hex: "64748B")
        }
    }
}
