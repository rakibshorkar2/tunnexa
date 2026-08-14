import SwiftUI

struct AddProxySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var proxyViewModel: ProxyViewModel
    
    var editingProxy: SOCKS5Proxy?
    
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var portText: String = "1080"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    
    // Testing state
    @State private var isTesting: Bool = false
    @State private var testResult: String?
    @State private var testLatencyMs: Int?
    @State private var testSuccess: Bool?
    
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0F172A").ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        
                        // Server Details Section
                        VStack(alignment: .leading, spacing: 14) {
                            Text("SERVER DETAILS")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "64748B"))
                                .tracking(1.0)
                            
                            // Name
                            CustomInputField(
                                label: "Display Name (Optional)",
                                placeholder: "e.g. My Fast US Proxy",
                                text: $name,
                                icon: "tag.fill"
                            )
                            
                            // Host
                            CustomInputField(
                                label: "Server Host / IP",
                                placeholder: "192.168.1.1 or proxy.example.com",
                                text: $host,
                                icon: "server.rack",
                                keyboardType: .URL,
                                autocapitalization: .never
                            )
                            
                            // Port
                            CustomInputField(
                                label: "Port",
                                placeholder: "1080",
                                text: $portText,
                                icon: "number",
                                keyboardType: .numberPad
                            )
                        }
                        .padding()
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(16)
                        
                        // Authentication Section
                        VStack(alignment: .leading, spacing: 14) {
                            Text("AUTHENTICATION (OPTIONAL)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "64748B"))
                                .tracking(1.0)
                            
                            // Username
                            CustomInputField(
                                label: "Username",
                                placeholder: "Leave empty if not required",
                                text: $username,
                                icon: "person.fill",
                                autocapitalization: .never
                            )
                            
                            // Password
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Password")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color(hex: "94A3B8"))
                                
                                HStack {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(hex: "64748B"))
                                        .frame(width: 24)
                                    
                                    if isPasswordVisible {
                                        TextField("Leave empty if not required", text: $password)
                                            .foregroundColor(.white)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                    } else {
                                        SecureField("Leave empty if not required", text: $password)
                                            .foregroundColor(.white)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                    }
                                    
                                    Button(action: {
                                        isPasswordVisible.toggle()
                                    }) {
                                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(hex: "64748B"))
                                    }
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(10)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(16)
                        
                        // Connection Test Box
                        VStack(spacing: 12) {
                            HStack {
                                Button(action: runConnectionTest) {
                                    HStack(spacing: 8) {
                                        if isTesting {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "bolt.fill")
                                        }
                                        Text(isTesting ? "Testing..." : "Test Connection")
                                    }
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(host.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.3) : Color(hex: "3B82F6"))
                                    .cornerRadius(12)
                                }
                                .disabled(isTesting || host.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            
                            if let result = testResult {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(testSuccess == true ? Color(hex: "10B981") : Color(hex: "EF4444"))
                                        .frame(width: 8, height: 8)
                                    
                                    Text(result)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(testSuccess == true ? Color(hex: "10B981") : Color(hex: "EF4444"))
                                    
                                    if let ms = testLatencyMs {
                                        Spacer()
                                        Text("\(ms) ms")
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                }
                                .padding(10)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(16)
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "EF4444"))
                                .multilineTextAlignment(.center)
                        }
                        
                        // Save Button
                        Button(action: saveProxy) {
                            Text(editingProxy != nil ? "Update Proxy" : "Save Proxy")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(hex: "10B981"))
                                .cornerRadius(14)
                                .shadow(color: Color(hex: "10B981").opacity(0.4), radius: 10, y: 4)
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                }
            }
            .navigationTitle(editingProxy != nil ? "Edit Proxy" : "Add SOCKS5 Proxy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "94A3B8"))
                }
            }
            .onAppear {
                if let proxy = editingProxy {
                    self.name = proxy.name
                    self.host = proxy.host
                    self.portText = "\(proxy.port)"
                    self.username = proxy.username ?? ""
                    self.password = KeychainHelper.shared.getPassword(forProxyId: proxy.id.uuidString) ?? ""
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func runConnectionTest() {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { return }
        guard let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0, port <= 65535 else {
            testResult = "Invalid port number"
            testSuccess = false
            return
        }
        
        isTesting = true
        testResult = nil
        testLatencyMs = nil
        testSuccess = nil
        
        let testProxy = SOCKS5Proxy(
            id: editingProxy?.id ?? UUID(),
            name: name,
            host: cleanHost,
            port: port,
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password
        )
        
        ProxyHealthTester.testLatency(proxy: testProxy) { latency, status in
            DispatchQueue.main.async {
                self.isTesting = false
                self.testLatencyMs = latency
                self.testResult = status
                self.testSuccess = (status == "Online")
            }
        }
    }
    
    private func saveProxy() {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else {
            errorMessage = "Server Host / IP is required."
            return
        }
        guard let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0, port <= 65535 else {
            errorMessage = "Port must be a valid number between 1 and 65535."
            return
        }
        
        if let editing = editingProxy {
            proxyViewModel.updateManualProxy(
                id: editing.id,
                name: name,
                host: cleanHost,
                port: port,
                username: username,
                password: password
            )
        } else {
            proxyViewModel.addManualProxy(
                name: name,
                host: cleanHost,
                port: port,
                username: username,
                password: password
            )
        }
        
        dismiss()
    }
}

// MARK: - Input Field Component

struct CustomInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "94A3B8"))
            
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "64748B"))
                    .frame(width: 24)
                
                TextField(placeholder, text: $text)
                    .foregroundColor(.white)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .disableAutocorrection(true)
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
        }
    }
}
