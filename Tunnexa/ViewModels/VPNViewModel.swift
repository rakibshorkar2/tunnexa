import Foundation
import SwiftUI
import Combine
import NetworkExtension

public class VPNViewModel: ObservableObject {
    @Published public var status: NEVPNStatus = .disconnected
    @Published public var sessionDuration: String = "00:00:00"
    @Published public var uploadSpeed: String = "0 B/s"
    @Published public var downloadSpeed: String = "0 B/s"
    @Published public var bytesSent: String = "0 B"
    @Published public var bytesReceived: String = "0 B"
    
    @Published public var errorMessage: String?
    
    private var vpnManager = VPNManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var connectionStartTime: Date?
    private let sharedDefaults: UserDefaults = UserDefaults(suiteName: "group.com.rakib.tunnexa") ?? .standard
    
    public init() {
        vpnManager.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                self?.status = newStatus
                self?.handleStatusChange(newStatus)
            }
            .store(in: &cancellables)
    }
    
    public func toggleConnection() {
        if status == .connected {
            vpnManager.stopVPN()
        } else if status == .disconnected {
            errorMessage = nil
            vpnManager.startVPN { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                        SharedLogging.log("Failed to start VPN: \(error.localizedDescription)", category: .vpn)
                    }
                }
            }
        }
    }
    
    private func handleStatusChange(_ newStatus: NEVPNStatus) {
        if newStatus == .connected {
            // Reset speeds and start timer
            connectionStartTime = Date()
            startTimer()
        } else if newStatus == .disconnected || newStatus == .invalid {
            stopTimer()
            sessionDuration = "00:00:00"
            uploadSpeed = "0 B/s"
            downloadSpeed = "0 B/s"
            
            // Do not reset total bytes immediately so user can see last session stats,
            // but reset speed variables in shared settings.
            sharedDefaults.set(0, forKey: "stat_upload_speed")
            sharedDefaults.set(0, forKey: "stat_download_speed")
        }
    }
    
    private func startTimer() {
        timer?.invalidate()
        
        // Reset local stats on new session start
        sharedDefaults.set(0, forKey: "stat_upload_bytes")
        sharedDefaults.set(0, forKey: "stat_download_bytes")
        sharedDefaults.set(0, forKey: "stat_upload_speed")
        sharedDefaults.set(0, forKey: "stat_download_speed")
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        connectionStartTime = nil
    }
    
    private func updateMetrics() {
        // 1. Session Duration
        if let startTime = connectionStartTime {
            let elapsed = Int(Date().timeIntervalSince(startTime))
            let hours = elapsed / 3600
            let minutes = (elapsed % 3600) / 60
            let seconds = elapsed % 60
            sessionDuration = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        
        // 2. Traffic Speed & Bytes
        let upSpeed = sharedDefaults.integer(forKey: "stat_upload_speed")
        let downSpeed = sharedDefaults.integer(forKey: "stat_download_speed")
        let totalUp = sharedDefaults.integer(forKey: "stat_upload_bytes")
        let totalDown = sharedDefaults.integer(forKey: "stat_download_bytes")
        
        uploadSpeed = formatBytesPerSecond(upSpeed)
        downloadSpeed = formatBytesPerSecond(downSpeed)
        
        bytesSent = formatBytes(totalUp)
        bytesReceived = formatBytes(totalDown)
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatBytesPerSecond(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        let speedStr = formatter.string(fromByteCount: Int64(bytes))
        return "\(speedStr)/s"
    }
}
