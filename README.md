# Tunnexa — System-Wide SOCKS5 VPN Client for iOS

Tunnexa is a native iOS SOCKS5 proxy client. On a **standalone (signed or per-version-signed) install** it tunnels all device traffic using Apple's **NetworkExtension** framework: a `NEPacketTunnelProvider` captures raw IP packets, a user-space engine (hev-socks5-tunnel via Tun2SocksKit) translates them into SOCKS5 streams, and a local Swift dispatcher applies routing rules and relays to the configured upstream proxies.

Tunnexa also runs inside **LiveContainer** or the **simulator**, where a system VPN is impossible: in those environments it detects the guest runtime and exposes the same dispatcher as an **in-app SOCKS5 proxy on `127.0.0.1:10808`** (with no system VPN involved). See [DEPLOYMENT.md](DEPLOYMENT.md) for mode details.

---

## Architecture Flow

```text
iPhone applications (Safari, Mail, Games, DNS)
        │
        ▼ [Virtual Interface capture]        (standalone mode only)
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
1. **Tunnexa (Main iOS Application)**: Manages proxy configurations, importing Clash-style configurations, testing proxy health (latency), configuring settings, and starting/stopping the tunnel (or the in-app proxy in LiveContainer/simulator).
2. **TunnexaPacketTunnel (Packet Tunnel Provider Extension)**: A network extension target that runs the virtual TUN interface. It captures raw IP packets, translates them into TCP/UDP streams via `Tun2SocksKit`, redirects them to the local SOCKS5 dispatcher, matches domain rules, and relays the payload to the remote proxies.
3. **Local SOCKS5 Dispatcher**: A custom server written in Swift using Apple's high-performance `Network` framework. Running locally (inside the extension's process, or inside the app process in in-app mode), it acts as a smart gateway, supporting TCP/UDP traffic forwarding, round-robin load-balancing, and domain rules matching.

---

## Features
- **True System-Wide Tunneling (standalone installs)**: Intercepts and tunnels all TCP and UDP traffic device-wide.
- **Runtime-aware mode selection**: detects standalone / LiveContainer / simulator environments and only attempts a system VPN where it is possible; elsewhere it surfaces the in-app proxy — never a fake "connected" VPN state.
- **Fail-Closed Kill Switch**: If the selected proxy fails or becomes unreachable, Tunnexa blocks traffic rather than falling back to direct, unprotected network routing.
- **DNS-over-SOCKS5**: Employs `mapdns` to capture local DNS queries on `198.18.0.2`, map domains to virtual IPs (e.g. `100.64.0.0/10`), and perform remote name resolution via domain SOCKS5 requests, preventing DNS leaks.
- **Clash YAML Configuration Import**: Supports importing `.yaml` / `.yml` configurations directly from the iOS Files app or Share Sheet.
- **Proxy Group Selector & Load Balancing**: Parses group selects and round-robin load balancers, switching between active proxies dynamically.
- **Proxy Health & Latency Tester**: Runs a staged RFC 1928/1929 SOCKS5 probe (TCP connect → greeting → authentication → CONNECT) against each proxy with per-stage timing, showing live latency and a precise failure stage when a proxy is unreachable.
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
1. Regenerates the Xcode project and verifies the generator is deterministic (the checked-in `project.pbxproj` must not change on re-generation).
2. Derives unique build numbers from the action run numbers.
3. Resolves SPM packages (such as `Tun2SocksKit`) with a dependency cache.
4. Runs the full unit test suite (routing, YAML parsing, SOCKS5 protocol, health tester, credential store, auto-reconnect, log redaction, environment detection, engine config, startup state machine) on an iOS Simulator.
5. Compiles both targets without signing restrictions.
6. Packages the app into an unsigned `.ipa` and `.zip` file and validates the packaging with `validate_ipa.py` (bundle IDs, embedded extension, Mach-O binaries, signing state; macOS runners additionally run `codesign`/`security`/`otool` checks).
7. Deploys a GitHub Release with the build number as tag (e.g., `build-123`) and uploads the release assets.

> **Honest limitation:** the CI artifact is unsigned. An unsigned bundle **cannot register a system-wide VPN provider** on a physical iPhone; use it with LiveContainer (in-app proxy mode) or re-sign it with a profile carrying the Network Extension entitlements. See `DEPLOYMENT.md`.

---

## Troubleshooting & Verification

### Local Diagnostic Panel
Inside the app, navigate to the **Diagnostics** tab. It reveals:
- Current tunnel interface status (Connected/Disconnected).
- Interface IP address (`198.18.0.1`), MTU, DNS mapping server (`198.18.0.2`), and credential storage mode.
- Total upload and download data.
- Live console log output with redacted credentials.
- An **Export** button that writes a redacted diagnostics bundle (state, settings, issues, log tail) to Files.

### Verifying Routing
1. Import the configuration file: `bypassempire (2).yaml`.
2. Navigate to **Proxies**, select a proxy, and tap "Test All". Confirm the status changes to "Online" or shows a latency.
3. Toggle the Main Switch on. Authorize the VPN prompt if requested.
4. Navigate to a test page like `https://google.com` or inspect IP outputs to verify that device traffic is passing through the selected proxy.
5. In **Settings**, toggle **Allow Local Network Bypass** to exclude local private IPs (`192.168.x.x`) from SOCKS5 routing.
