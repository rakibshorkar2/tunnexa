import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.appearance) private var appearance: String = "System"

    @State private var autoConnect = false
    @State private var reconnect = false
    @State private var allowLocal = false
    @State private var ipv6Enabled = false
    @State private var killSwitch = false
    @State private var mtuText: String = ""
    @State private var mtuIsValid = true

    @State private var settings = SharedSettings()

    var body: some View {
        ZStack {
            Color(hex: "0F172A").ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("Settings")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding()
                .background(Color(hex: "1E293B").opacity(0.5))

                Form {
                    Section(header: Text("VPN CONFIGURATION").foregroundColor(Color(hex: "64748B"))) {
                        Toggle("Auto-connect on launch", isOn: $autoConnect)
                            .onChange(of: autoConnect) { _, val in
                                settings.autoConnect = val
                            }

                        Toggle("Auto-reconnect on disconnect", isOn: $reconnect)
                            .onChange(of: reconnect) { _, val in
                                settings.autoReconnect = val
                            }

                        Toggle("Allow Local Network Bypass", isOn: $allowLocal)
                            .onChange(of: allowLocal) { _, val in
                                settings.allowLocalNetwork = val
                            }

                        Toggle("Enable IPv6 Routing", isOn: $ipv6Enabled)
                            .onChange(of: ipv6Enabled) { _, val in
                                settings.ipv6Enabled = val
                            }

                        Toggle("Kill Switch (Block if VPN fails)", isOn: $killSwitch)
                            .onChange(of: killSwitch) { _, val in
                                settings.killSwitchEnabled = val
                            }

                        HStack {
                            Text("Tunnel MTU Size")
                            Spacer()
                            TextField("9000", text: $mtuText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(mtuIsValid ? .white : Color(hex: "F43F5E"))
                                .onChange(of: mtuText) { _, val in
                                    validateMTU(val)
                                }
                        }
                        if !mtuIsValid {
                            Text("MTU must be between \(MTULimit.minimum) and \(MTULimit.maximum). Keeping last valid value.")
                                .font(.caption)
                                .foregroundColor(Color(hex: "F43F5E"))
                        }
                        Text("Kill switch: when enabled, traffic is blocked fail-closed at the routing level and the tunnel auto-connects on network changes (best-effort by iOS).")
                            .font(.caption)
                            .foregroundColor(Color(hex: "64748B"))
                    }
                    .listRowBackground(Color.white.opacity(0.02))

                    Section(header: Text("APPEARANCE").foregroundColor(Color(hex: "64748B"))) {
                        Picker("Theme Mode", selection: $appearance) {
                            Text("System").tag("System")
                            Text("Light").tag("Light")
                            Text("Dark").tag("Dark")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    .listRowBackground(Color.white.opacity(0.02))

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
                        HStack {
                            Text("Credential Storage")
                            Spacer()
                            Text(credentialStorageMode)
                                .foregroundColor(credentialModeColor)
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
        autoConnect = settings.autoConnect
        reconnect = settings.autoReconnect
        allowLocal = settings.allowLocalNetwork
        ipv6Enabled = settings.ipv6Enabled
        killSwitch = settings.killSwitchEnabled

        let mtu = settings.mtuOrDefault
        mtuText = String(mtu)
        mtuIsValid = true
    }

    private func validateMTU(_ text: String) {
        guard let value = Int(text) else {
            mtuIsValid = text.isEmpty
            return
        }
        if MTULimit.isValid(value) {
            settings.mtu = value
            mtuIsValid = true
        } else {
            mtuIsValid = false
        }
    }

    private var credentialStorageMode: String {
        return KeychainHelper.shared.activeMode.rawValue
    }

    private var credentialModeColor: Color {
        switch KeychainHelper.shared.activeMode {
        case .keychain, .keychainSharedGroup:
            return Color(hex: "10B981")
        case .insecureFallback, .unavailable:
            return Color(hex: "F59E0B")
        }
    }

    private var buildNumber: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}