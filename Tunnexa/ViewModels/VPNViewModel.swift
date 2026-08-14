import Foundation
import SwiftUI
import Combine
import NetworkExtension

/// Bridges `VPNManager` state to SwiftUI with formatted metrics.
public class VPNViewModel: ObservableObject {

    @Published public private(set) var state: TunnelState = .unavailable
    @Published public private(set) var isBusy: Bool = false
    @Published public private(set) var sessionDuration: String = "00:00:00"
    @Published public private(set) var uploadSpeed: String = "0 B/s"
    @Published public private(set) var downloadSpeed: String = "0 B/s"
    @Published public private(set) var bytesSent: String = "0 B"
    @Published public private(set) var bytesReceived: String = "0 B"

    @Published public var activeError: VPNErrorDetails?

    private let vpnManager = VPNManager.shared
    private let settings = SharedSettings()
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var connectionStartTime: Date?

    public init() {
        vpnManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.state = newState
                self?.handleStateChange(newState)
            }
            .store(in: &cancellables)

        vpnManager.$isBusy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] busy in
                self?.isBusy = busy
            }
            .store(in: &cancellables)
    }

    public func toggleConnection() {
        switch state {
        case .connected:
            vpnManager.stopVPN()
        case .disconnected, .failed:
            activeError = nil
            vpnManager.startVPN { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.activeError = nil
                    case .failure(let errorDetails):
                        self?.activeError = errorDetails
                    }
                }
            }
        case .connecting, .reasserting, .preparing, .disconnecting:
            break // in progress
        case .unavailable, .invalid:
            activeError = VPNErrorDetails(
                domain: "Tunnexa.State",
                code: 12,
                message: "The VPN profile is unavailable or invalid. Re-open the app or re-create the profile.",
                environment: VPNEnvironmentDetector.detectEnvironment()
            )
        }
    }

    private func handleStateChange(_ newState: TunnelState) {
        if newState.isConnected {
            connectionStartTime = Date()
            startTimer()
        } else if newState == .disconnected || newState == .failed || newState == .unavailable || newState == .invalid {
            stopTimer()
            sessionDuration = "00:00:00"
            uploadSpeed = "0 B/s"
            downloadSpeed = "0 B/s"
            settings.set(Int64(0), forKey: SettingsKey.statUploadSpeed)
            settings.set(Int64(0), forKey: SettingsKey.statDownloadSpeed)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        // Reset per-session counters.
        settings.set(Int64(0), forKey: SettingsKey.statUploadBytes)
        settings.set(Int64(0), forKey: SettingsKey.statDownloadBytes)
        settings.set(Int64(0), forKey: SettingsKey.statUploadSpeed)
        settings.set(Int64(0), forKey: SettingsKey.statDownloadSpeed)
        settings.set(Int64(Date().timeIntervalSince1970), forKey: SettingsKey.statTunnelStart)

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
        if let startTime = connectionStartTime {
            let elapsed = Int(Date().timeIntervalSince(startTime))
            sessionDuration = String(format: "%02d:%02d:%02d", elapsed / 3600, (elapsed % 3600) / 60, elapsed % 60)
        }

        let upSpeed = settings.int64(SettingsKey.statUploadSpeed)
        let downSpeed = settings.int64(SettingsKey.statDownloadSpeed)
        let totalUp = settings.int64(SettingsKey.statUploadBytes)
        let totalDown = settings.int64(SettingsKey.statDownloadBytes)

        uploadSpeed = formatBytesPerSecond(upSpeed)
        downloadSpeed = formatBytesPerSecond(downSpeed)
        bytesSent = formatBytes(totalUp)
        bytesReceived = formatBytes(totalDown)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatBytesPerSecond(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: bytes))/s"
    }
}