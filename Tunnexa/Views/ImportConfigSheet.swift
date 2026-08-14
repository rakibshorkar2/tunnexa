import SwiftUI
import UniformTypeIdentifiers

struct ImportConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var proxyViewModel: ProxyViewModel
    
    @State private var selectedTab = 0
    @State private var rawYamlText: String = ""
    @State private var subscriptionUrl: String = ""
    @State private var isDownloading: Bool = false
    @State private var isFilePickerPresented: Bool = false
    
    @State private var statusMessage: String?
    @State private var isSuccess: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0F172A").ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    // Segmented Mode Selector
                    Picker("Import Mode", selection: $selectedTab) {
                        Text("Paste Text").tag(0)
                        Text("Subscription URL").tag(1)
                        Text("Pick File").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    .background(Color(hex: "1E293B").opacity(0.6))
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            
                            // Tab 0: Paste YAML Text
                            if selectedTab == 0 {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("PASTE CLASH / SOCKS5 YAML")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(Color(hex: "64748B"))
                                            .tracking(1.0)
                                        Spacer()
                                        
                                        // Paste from Clipboard Button
                                        Button(action: pasteFromClipboard) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "doc.on.clipboard")
                                                Text("Paste")
                                            }
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(Color(hex: "38BDF8"))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color(hex: "38BDF8").opacity(0.1))
                                            .cornerRadius(8)
                                        }
                                        
                                        // Sample Template Button
                                        Button(action: loadSampleTemplate) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "wand.and.stars")
                                                Text("Sample")
                                            }
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(Color(hex: "A855F7"))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color(hex: "A855F7").opacity(0.1))
                                            .cornerRadius(8)
                                        }
                                    }
                                    
                                    // Text Editor
                                    ZStack(alignment: .topLeading) {
                                        if rawYamlText.isEmpty {
                                            Text("Paste Clash YAML configuration content here...\n\nproxies:\n  - name: 'US Server'\n    type: socks5\n    server: 1.2.3.4\n    port: 1080")
                                                .font(.system(size: 13, design: .monospaced))
                                                .foregroundColor(Color(hex: "475569"))
                                                .padding(12)
                                        }
                                        
                                        TextEditor(text: $rawYamlText)
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(.white)
                                            .scrollContentBackground(.hidden)
                                            .background(Color.white.opacity(0.04))
                                            .cornerRadius(12)
                                            .frame(minHeight: 220, maxHeight: 320)
                                            .padding(4)
                                    }
                                    .background(Color.white.opacity(0.02))
                                    .cornerRadius(14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                    
                                    // Import Action
                                    Button(action: importText) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                            Text("Import YAML Configuration")
                                        }
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(rawYamlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : Color(hex: "6366F1"))
                                        .cornerRadius(14)
                                    }
                                    .disabled(rawYamlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .padding(.top, 6)
                                }
                                .padding()
                            }
                            
                            // Tab 1: Subscription URL
                            else if selectedTab == 1 {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("SUBSCRIPTION / REMOTE YAML URL")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(hex: "64748B"))
                                        .tracking(1.0)
                                    
                                    HStack {
                                        Image(systemName: "link")
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(hex: "64748B"))
                                            .frame(width: 24)
                                        
                                        TextField("https://example.com/config.yaml", text: $subscriptionUrl)
                                            .foregroundColor(.white)
                                            .keyboardType(.URL)
                                            .textInputAutocapitalization(.never)
                                            .disableAutocorrection(true)
                                        
                                        if !subscriptionUrl.isEmpty {
                                            Button(action: { subscriptionUrl = "" }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(Color(hex: "64748B"))
                                            }
                                        }
                                    }
                                    .padding(14)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(12)
                                    
                                    HStack {
                                        Button(action: {
                                            if let clip = UIPasteboard.general.string {
                                                subscriptionUrl = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                            }
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "doc.on.clipboard")
                                                Text("Paste URL")
                                            }
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundColor(Color(hex: "38BDF8"))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color(hex: "38BDF8").opacity(0.1))
                                            .cornerRadius(10)
                                        }
                                        
                                        Spacer()
                                    }
                                    
                                    Button(action: downloadAndImport) {
                                        HStack(spacing: 8) {
                                            if isDownloading {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                    .scaleEffect(0.8)
                                            } else {
                                                Image(systemName: "arrow.down.circle.fill")
                                            }
                                            Text(isDownloading ? "Downloading..." : "Download & Import")
                                        }
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(subscriptionUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : Color(hex: "10B981"))
                                        .cornerRadius(14)
                                    }
                                    .disabled(isDownloading || subscriptionUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .padding(.top, 10)
                                }
                                .padding()
                            }
                            
                            // Tab 2: Pick File
                            else {
                                VStack(spacing: 20) {
                                    Image(systemName: "doc.badge.arrow.up")
                                        .font(.system(size: 48))
                                        .foregroundColor(Color(hex: "6366F1"))
                                        .padding(.top, 20)
                                    
                                    Text("Select a Clash YAML file (.yaml or .yml) from your device Files.")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(Color(hex: "94A3B8"))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                    
                                    Button(action: {
                                        isFilePickerPresented = true
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "folder.fill")
                                            Text("Browse Files")
                                        }
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color(hex: "6366F1"))
                                        .cornerRadius(14)
                                    }
                                    .padding(.horizontal)
                                }
                                .padding()
                            }
                            
                            // Status / Feedback Message
                            if let msg = statusMessage {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundColor(isSuccess ? Color(hex: "10B981") : Color(hex: "EF4444"))
                                        .font(.system(size: 18))
                                    
                                    Text(msg)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(isSuccess ? Color(hex: "10B981") : Color(hex: "EF4444"))
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .fileImporter(
                isPresented: $isFilePickerPresented,
                allowedContentTypes: [.item, .plainText, .text, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let firstUrl = urls.first {
                        proxyViewModel.importYAML(from: firstUrl)
                        if let msg = proxyViewModel.importStatusMessage {
                            self.statusMessage = msg
                            self.isSuccess = msg.contains("Import complete")
                            if self.isSuccess {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    dismiss()
                                }
                            }
                        }
                    }
                case .failure(let error):
                    self.statusMessage = "File selection error: \(error.localizedDescription)"
                    self.isSuccess = false
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func pasteFromClipboard() {
        if let clip = UIPasteboard.general.string {
            rawYamlText = clip
        }
    }
    
    private func loadSampleTemplate() {
        rawYamlText = """
proxies:
  - name: "HK Fast Node"
    type: socks5
    server: 1.2.3.4
    port: 1080
    username: myuser
    password: mypassword

  - name: "US Backup Node"
    type: socks5
    server: 5.6.7.8
    port: 1080

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - "HK Fast Node"
      - "US Backup Node"

rules:
  - MATCH,PROXY
"""
    }
    
    private func importText() {
        let clean = rawYamlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        
        proxyViewModel.importYAMLText(content: clean)
        if let msg = proxyViewModel.importStatusMessage {
            self.statusMessage = msg
            self.isSuccess = msg.contains("Import complete")
            if self.isSuccess {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                }
            }
        }
    }
    
    private func downloadAndImport() {
        isDownloading = true
        statusMessage = nil
        
        proxyViewModel.importYAMLFromURL(urlString: subscriptionUrl) { success, message in
            self.isDownloading = false
            self.statusMessage = message
            self.isSuccess = success
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                }
            }
        }
    }
}
