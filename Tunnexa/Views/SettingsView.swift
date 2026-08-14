import SwiftUI

struct SettingsView: View {
    @AppStorage("setting_appearance") private var appearance: String = "System"
    
    @State private var autoConnect = false
    @State private var reconnect = false
    @State private var allowLocal = false
    @State private var ipv6Enabled = false
    @State private var killSwitch = false
    @State private var mtuSize: String = "9000"
    
    private let sharedDefaults = UserDefaults(suiteName: "group.com.rakib.tunnexa")!
    
    var body: some View {
        ZStack {
            Color(hex: "0F172A").ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding()
                .background(Color(hex: "1E293B").opacity(0.5))
                
                Form {
                    // 1. VPN Section
                    Section(header: Text("VPN CONFIGURATION").foregroundColor(Color(hex: "64748B"))) {
                        Toggle("Auto-connect on launch", isOn: $autoConnect)
                            .onChange(of: autoConnect) { _, val in
                                sharedDefaults.set(val, forKey: "setting_auto_connect")
                            }
                        
                        Toggle("Auto-reconnect on disconnect", isOn: $reconnect)
                            .onChange(of: reconnect) { _, val in
                                sharedDefaults.set(val, forKey: "setting_reconnect")
                            }
                        
                        Toggle("Allow Local Network Bypass", isOn: $allowLocal)
                            .onChange(of: allowLocal) { _, val in
                                sharedDefaults.set(val, forKey: "setting_allow_local")
                            }
                        
                        Toggle("Enable IPv6 Routing", isOn: $ipv6Enabled)
                            .onChange(of: ipv6Enabled) { _, val in
                                sharedDefaults.set(val, forKey: "setting_ipv6")
                            }
                        
                        Toggle("Kill Switch (Block if VPN fails)", isOn: $killSwitch)
                            .onChange(of: killSwitch) { _, val in
                                sharedDefaults.set(val, forKey: "setting_kill_switch")
                            }
                        
                        HStack {
                            Text("Tunnel MTU Size")
                            Spacer()
                            TextField("9000", text: $mtuSize)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.white)
                                .onChange(of: mtuSize) { _, val in
                                    if let intVal = Int(val) {
                                        sharedDefaults.set(intVal, forKey: "setting_mtu")
                                    }
                                }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.02))
                    
                    // 2. Appearance Section
                    Section(header: Text("APPEARANCE").foregroundColor(Color(hex: "64748B"))) {
                        Picker("Theme Mode", selection: $appearance) {
                            Text("System").tag("System")
                            Text("Light").tag("Light")
                            Text("Dark").tag("Dark")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    .listRowBackground(Color.white.opacity(0.02))
                    
                    // 3. About Section
                    Section(header: Text("ABOUT").foregroundColor(Color(hex: "64748B"))) {
                        HStack {
                            Text("App Name")
                            Spacer()
                            Text("Tunnexa")
                                .foregroundColor(Color(hex: "94A3B8"))
                        }
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("1.0.0")
                                .foregroundColor(Color(hex: "94A3B8"))
                        }
                        HStack {
                            Text("Build Number")
                            Spacer()
                            Text(buildNumber)
                                .foregroundColor(Color(hex: "94A3B8"))
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.02))
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .onAppear(perform: loadSettings)
        .foregroundColor(.white)
    }
    
    // MARK: - Logic
    
    private func loadSettings() {
        autoConnect = sharedDefaults.bool(forKey: "setting_auto_connect")
        reconnect = sharedDefaults.bool(forKey: "setting_reconnect")
        allowLocal = sharedDefaults.bool(forKey: "setting_allow_local")
        ipv6Enabled = sharedDefaults.bool(forKey: "setting_ipv6")
        killSwitch = sharedDefaults.bool(forKey: "setting_kill_switch")
        
        let mtu = sharedDefaults.integer(forKey: "setting_mtu")
        mtuSize = mtu == 0 ? "9000" : String(mtu)
    }
    
    private var buildNumber: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
