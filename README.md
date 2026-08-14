# Tunnexa — System-Wide SOCKS5 VPN Client for iOS

Tunnexa is a native iOS SOCKS5 proxy client and VPN application. It intercepts all device network traffic (TCP, UDP, DNS, and IPv6 where supported) using Apple's **NetworkExtension** framework and routes it through a custom user-space packet-to-SOCKS5 routing architecture.

---

## Architecture Flow

```text
iPhone applications (Safari, Mail, Games, DNS)
        │
        ▼ [Virtual Interface capture]
iOS Network Stack
        │
        ▼ [Raw IP packet flow]
NEPacketTunnelProvider (TunnexaPacketTunnel)
        │
        ▼ [Packet-to-TCP/UDP stream translation]
hev-socks5-tunnel (via Tun2SocksKit)
        │
        ▼ [Local SOCKS5 CONNECT/UDP ASSOCIATE redirect to 127.0.0.1:10808]
Local SOCKS5 Dispatcher & Router (Swift NWListener)
        │ (Evaluates routing rules & proxy groups)
        ├──[Direct Rule]───────► DIRECT Internet
        └──[Proxy Rule]────────► Configured Upstream SOCKS5 Proxy ──► Internet
```

### Components
1. **Tunnexa (Main iOS Application)**: Manages proxy configurations, importing Clash-style configurations, testing proxy health (latency), configuring settings, and starting/stopping the tunnel.
2. **TunnexaPacketTunnel (Packet Tunnel Provider Extension)**: A network extension target that runs the virtual TUN interface. It captures raw IP packets, translates them into TCP/UDP streams via `Tun2SocksKit`, redirects them to the local SOCKS5 dispatcher, matches domain rules, and relays the payload to the remote proxies.
3. **Local SOCKS5 Dispatcher**: A custom server written in Swift using Apple's high-performance `Network` framework. Running locally within the extension's process, it acts as a smart gateway, supporting TCP/UDP traffic forwarding, round-robin load-balancing, and domain rules matching.

---

## Features
- **True System-Wide Tunneling**: Intercepts and tunnels all TCP and UDP traffic device-wide.
- **Fail-Closed Kill Switch**: If the selected proxy fails or becomes unreachable, Tunnexa blocks traffic rather than falling back to direct, unprotected network routing.
- **DNS-over-SOCKS5**: Employs `mapdns` to capture local DNS queries on `198.18.0.2`, map domains to virtual IPs (e.g. `100.64.0.0/10`), and perform remote name resolution via domain SOCKS5 requests, preventing DNS leaks.
- **Clash YAML Configuration Import**: Supports importing `.yaml` / `.yml` configurations directly from the iOS Files app or Share Sheet.
- **Proxy Group Selector & Load Balancing**: Parses group selects and round-robin load balancers, switching between active proxies dynamically.
- **Proxy Health & Latency Tester**: Tests TCP handshake and HTTP GET performance directly through each proxy, showing connection delays.
- **Security First**: Automatically sanitizes passwords and usernames, redacting them from connection logs and sharing configurations without plain credentials.

---

## How to Build the Project

### 1. Generate the Xcode Project
Because maintaining bulky `.xcodeproj` project files leads to conflicts in Git, Tunnexa is generated dynamically. You can generate the project using our Python utility:

```bash
# Run the generator script in the workspace root
python generate_project.py
```
This script immediately outputs the `Tunnexa.xcodeproj` directory, plists, and target entitlements.

*(Alternatively, you can run `xcodegen generate` if you have XcodeGen installed via Homebrew).*

### 2. Network Extension Signing & Provisioning (Important)
Apple restricts `NEPacketTunnelProvider` network extensions to signed developer provisions. 
- Open `Tunnexa.xcodeproj` in Xcode.
- Go to the **Signing & Capabilities** tab for both the `Tunnexa` and `TunnexaPacketTunnel` targets.
- Enable **App Groups** and choose a shared identifier (e.g., `group.yourdomain.tunnexa`).
- Enable **Network Extensions** and select **Packet Tunnel Provider**.
- Set your Developer Team ID. Xcode will generate matching provisioning profiles.

*Note: For local iOS Simulator runs or unsigned archiving in CI, the code is configured to compile and archive without code signing, utilizing a fallback obfuscated UserDefaults database for passwords instead of Keychain sharing groups.*

### 3. CI/CD Releases (GitHub Actions)
Tunnexa includes a `.github/workflows/build.yml` file which runs on every push:
1. Derives unique build numbers from the action run numbers.
2. Resolves SPM packages (such as `Tun2SocksKit`).
3. Compiles both targets without signing restrictions.
4. Packages the app into an unsigned `.ipa` and `.zip` file.
5. Deploys a GitHub Release with the build number as tag (e.g., `build-123`) and uploads the release assets.

---

## Troubleshooting & Verification

### Local Diagnostic Panel
Inside the app, navigate to the **Diagnostics** tab. It reveals:
- Current tunnel interface status (Connected/Disconnected).
- Interface IP address (`198.18.0.1`), MTU, and DNS mapping server (`198.18.0.2`).
- Total upload and download data.
- Live console log output with redacted credentials.

### Verifying Routing
1. Import the configuration file: `bypassempire (2).yaml`.
2. Navigate to **Proxies**, select a proxy, and tap "Test All". Confirm the status changes to "Online" or shows a latency.
3. Toggle the Main Switch on. Authorize the VPN prompt if requested.
4. Navigate to a test page like `https://google.com` or inspect IP outputs to verify that device traffic is passing through the selected proxy.
5. In **Settings**, toggle **Allow Local Network Bypass** to exclude local private IPs (`192.168.x.x`) from SOCKS5 routing.
