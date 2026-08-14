# Tunnexa — Deployment & Signing Requirements

## Architecture Overview

Tunnexa is a **system-wide SOCKS5 VPN** using Apple's NetworkExtension stack:

```
Tunnexa.app
└── PlugIns/
    └── TunnexaPacketTunnel.appex   ← NEPacketTunnelProvider (Tun2SocksKit)
```

The application routes all device-wide IP traffic through a virtual TUN interface provided by `NEPacketTunnelProvider`. Traffic is then relayed through the selected SOCKS5 upstream proxy via a local packet dispatcher.

---

## Required Capabilities & Entitlements

### Main App (`com.rakib.tunnexa`)

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.rakib.tunnexa</string>
</array>
<key>com.apple.developer.networking.networkextension</key>
<array>
    <string>packet-tunnel-provider</string>
</array>
```

### Packet Tunnel Extension (`com.rakib.tunnexa.PacketTunnel`)

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.rakib.tunnexa</string>
</array>
<key>com.apple.developer.networking.networkextension</key>
<array>
    <string>packet-tunnel-provider</string>
</array>
```

---

## Supported Installation Methods

### ✅ SUPPORTED: Standalone iOS App (Correctly Provisioned)

Install via:
- **TrollStore** (preferred for unsigned permanent installation on supported firmware)
- **AltStore / SideStore** (7-day certificate signing, requires Apple ID re-sign)
- **Sideloadly** (7-day certificate signing, requires Apple ID re-sign)
- **Apple Developer Certificate** (requires paid Apple Developer Program membership with NetworkExtension capability explicitly enabled in App ID)

When installed as a standalone app using one of the above methods with a valid provisioning configuration that includes:
- App Group `group.com.rakib.tunnexa`
- Network Extension capability `packet-tunnel-provider`

The full Packet Tunnel VPN pipeline functions correctly:

```
iOS → NETunnelProviderManager → NEPacketTunnelProvider
→ TUN virtual interface → Tun2SocksKit → Local SOCKS5 dispatcher
→ Upstream SOCKS5 proxy → Internet
```

---

### ❌ UNSUPPORTED: LiveContainer Guest App

```
LiveContainer → Tunnexa (guest) → TunnexaPacketTunnel.appex
```

**This configuration cannot function as a system-wide VPN. This is not a Tunnexa code defect.**

Reason: iOS requires each `NEPacketTunnelProvider` app extension to be independently registered with the iOS kernel via `NETunnelProviderManager.saveToPreferences()`. This operation requires:

1. The calling process has a valid entitlement signed by Apple (`com.apple.developer.networking.networkextension`).
2. The **Packet Tunnel app extension** (`TunnexaPacketTunnel.appex`) is registered as an independent extension identity with iOS SpringBoard/launchd.

LiveContainer runs guest apps inside its own sandbox and process space. Guest applications' embedded `*.appex` extensions are **not registered** with iOS. As a result:

- `NETunnelProviderManager.loadAllFromPreferences()` returns `permission denied`
- `saveToPreferences()` fails
- The Packet Tunnel extension cannot be launched by iOS

**No source code change in Tunnexa can overcome this iOS platform-level restriction.**

---

## Required Actions for Standalone Deployment

### Option A: TrollStore (Recommended for jailbreak-adjacent devices)

1. Build the IPA using the CI/CD workflow (macos-26, Xcode 26.6).
2. Download the unsigned IPA from GitHub Releases.
3. Open TrollStore on device → Install App → select the IPA.
4. TrollStore will install with permanent code signature that satisfies the NetworkExtension entitlement.
5. On first launch, iOS will prompt to allow VPN configuration. **Tap Allow.**
6. The VPN profile is saved. VPN tunnel can now start.

### Option B: Apple Developer Certificate (Full Provisioning)

1. Register an App ID `com.rakib.tunnexa` in the Apple Developer portal.
2. Enable **Network Extensions** capability under the App ID.
3. Create a provisioning profile including the `packet-tunnel-provider` entitlement.
4. Create a matching App ID `com.rakib.tunnexa.PacketTunnel` for the extension.
5. Create a provisioning profile for the extension.
6. Build and archive with Xcode using both profiles.
7. Export for Ad Hoc or App Store distribution.

---

## IPA Package Validation

A validation script is provided to verify IPA packaging correctness before sideloading:

```bash
python3 validate_ipa.py --ipa Tunnexa-unsigned-build-N.ipa
```

The script checks:
- Main app bundle identifier = `com.rakib.tunnexa`
- Main app executable is present
- Extension is embedded in `PlugIns/TunnexaPacketTunnel.appex`
- Extension bundle identifier = `com.rakib.tunnexa.PacketTunnel`
- `CFBundlePackageType = XPC!`
- `NSExtensionPointIdentifier = com.apple.networkextension.packet-tunnel`
- `NSExtensionPrincipalClass` is set to `PacketTunnelProvider`
- Extension executable is present
- Signing state detected and reported (signed bundles must carry `_CodeSignature` + `embedded.mobileprovision`)
- App and extension signing states are consistent

---

## Expected VPN Lifecycle (Standalone)

```
1. App launches
2. VPNManager detects environment → .standalone
3. loadAllFromPreferences() checks for existing Tunnexa Packet Tunnel profile
4. If found: reuse existing profile
5. If not found: create NETunnelProviderProtocol + NETunnelProviderManager → saveToPreferences()
   → iOS shows "Tunnexa would like to add VPN configurations" → user taps Allow
   → Reload preferences to get system-persisted handle
6. startVPNTunnel() invoked
7. iOS launches TunnexaPacketTunnel.appex process
8. PacketTunnelProvider.startTunnel() installs NEPacketTunnelNetworkSettings
9. Local SOCKS5 dispatcher (port 10808) starts; Tun2SocksKit is launched on a dedicated thread with the TUN fd, pointed at the loopback dispatcher
10. All device traffic routes through TUN → dispatcher (rules & groups) → SOCKS5 proxy
11. UI displays Connected status; a sampler reports upload/download statistics every second
12. stopVPN() → PacketTunnelProvider.stopTunnel() → dispatcher stopped → Tun2SocksKit quit + join (thread exits cleanly)
```

---

## Routing Model

| Traffic | Routed Via |
|---------|-----------|
| Default IPv4 (0.0.0.0/0) | TUN → SOCKS5 proxy |
| Default IPv6 (::/0) | TUN → SOCKS5 proxy (if enabled) |
| DNS queries | Captured by Tun2SocksKit mapdns on 198.18.0.2 |
| RFC 1918 private ranges (if allow-local=true) | Excluded from tunnel, direct |
| SOCKS5 server IP itself | Excluded from tunnel (prevents routing loop) |

**Fail-closed routing:** when no rule matches and no proxy/group is selected, the dispatcher answers connections with SOCKS5 REP 0x02 (not allowed) — traffic is blocked, never implicitly leaked direct. When the kill switch is enabled, a `NEOnDemandRuleConnect` rule additionally blocks non-VPN traffic at the system level.

**Automatic reconnection:** on unexpected tunnel failures, the app retries with a backoff ladder (1, 2, 4, 8, 15, 30 s) up to 5 consecutive attempts, resetting the counter after a stable connection or a manual disconnect.

Virtual TUN subnet: `198.18.0.0/24`
Virtual TUN IPv4 address: `198.18.0.1`
DNS intercept address: `198.18.0.2`
Local proxy dispatcher port: `10808`
