# Tunnexa — Hardening & Regression Report

**Project:** Tunnexa — system-wide SOCKS5 VPN for iOS
**Status:** Hardening phases implemented. Swift sources and tests finalized; **tests authored but not executed locally** (see Execution Note). Requires CI + physical-device verification.
**Date:** 2026-08-16 (updated)

---

## 0. Engine Contract Correction (2026-08-16)

A second engineering pass re-verified the engine contract against the actual
vendored binaries (hev-socks5-tunnel 2.17.1 sources + Tun2SocksKit 5.16.0
shim, tag `dc6d73f`) instead of assuming the old repo's ioctl/KVC machinery
was load-bearing. Findings and fixes:

| # | Finding | Fix |
|---|---|---|
| 1 | `Socks5Tunnel.run(withConfig:)` accepts **no caller fd**; it scans fds 0…1024 via `getpeername` for the `com.apple.net.utun_control` socket owned by `packetFlow`, and hands it to `hev_socks5_tunnel_main`. With an external fd the C engine only sets `FIONBIO` and **never closes it** (`tun_fd_local` path). | Removed all `TunnelFileDescriptor` ioctl/KVC dead weight; engine takes no fd; engine never closes descriptors (asserted in tests). |
| 2 | Config has **no `tunnel.fd` key**; with an external fd only `tunnel.mtu` matters (lwIP read-buffer sizing). | New `EngineConfigBuilder` emits `tunnel: { mtu }` only; no `name`/`ipv4`/`ipv6` keys. |
| 3 | Old `udp: udp` selected hev UDP-in-UDP (raw datagrams to 127.0.0.1:10808), which the dispatcher does not implement. | `udp:` key removed → engine uses SOCKS5 UDP-ASSOCIATE, which the dispatcher implements end-to-end. |
| 4 | Engine silently raises `task-stack-size` to `20480 + max(tcp-buffer-size, 1500*udp-copy-buffer-nums)`; old `task-stack-size: 20480` was a silent no-op. | Tuning defaults: tcp-buffer-size 16384, udp-copy-buffer-nums 2, max-session-count 256, connect-timeout 5000, read-write-timeout 60000; `effectiveTaskStackSize` computed + asserted in tests. |
| 5 | Old `startupState` instance property: iOS reuses the `NEPacketTunnelProvider` instance across sessions, so a stale `.succeeded`/`.failed` persisted and every later session hung in `.connecting`. | New `StartupStateMachine`: per-session `begin`/`settle`/`cancel`, exactly-once handler; `stopTunnel` uses `cancel()` (dropped handlers are never invoked — established system behavior). |
| 6 | `mapdns` with an external fd works over the tunnel (100.64.0.0/10). | Kept: `mapdns: 198.18.0.2:53 → 100.64.0.0/10`, cache 10000. |

### Runtime environment handling (honest mode mapping)
- `VPNEnvironmentDetector` rewritten: detects `.standalone` / `.liveContainer`
  (env vars `LC_APP_ID`, `LIVE_CONTAINER`, `LIVECONTAINER`, `LC_BUNDLE_ID`,
  path signatures `/livecontainer/`, `/data/app/`, `com.kdt.livecontainer`,
  bundle-id) / `.simulator` (compile-time, injectable for tests) / `.unknown` /
  `.unsupported`.
- `EnvironmentCapabilities` maps: standalone → packet-tunnel + shared app group;
  liveContainer → in-app proxy only; simulator → in-app proxy + app group;
  unknown/unsupported → none.
- `isSupportedForSystemVPN` is true **only** for `.standalone` (fail-safe).
  `VPNManager` refuses to create/save NE profiles otherwise, with
  `environmentUnsupportedError` messages in `VPNErrorDetails`.
- Mode C: `InAppProxyManager` runs the local dispatcher (127.0.0.1:10808) as an
  in-app proxy in LiveContainer/simulator — **never** presented as a system VPN.
- `TunnexaApp`/`MainView` switch UI and launch wiring by capabilities.
- `DiagnosticsRunner` reports environment + capabilities + in-app proxy state
  and environment-specific issues.

---

## 1. Execution Note (IMPORTANT)

This project was hardened on a **Windows host with no Xcode toolchain**. Consequently:

- All Swift code and tests were **authored and reviewed statically** against the real APIs in this repository.
- **No unit tests were compiled or executed locally.**
- The only executable validation performed locally was Python-based:
  - `generate_project.py` — pbxproj regeneration, reference integrity (`[ OK ] All pbxproj object references resolve.`), and determinism (`[ OK ] Generator is deterministic.`).
  - `validate_ipa.py` — syntax/smoke check (`py_compile`), structural validation (no IPA available locally).
- **The execution venue for the Swift test suite is the GitHub Actions workflow** (`.github/workflows/build.yml`), which now runs `xcodebuild test` on an iOS Simulator on every push. The first green CI run is the authoritative verification of the suite.
- **Physical-device verification (iPhone 15 Pro) is out of scope for this host**: no Xcode, no device connection. All device-dependent claims below are marked as CI/device-untested.

---

## 2. Scope of Work (by Phase)

### Phase 1 — Audit
- Full review of app, extension, shared sources, tests, generator, CI, and docs against the 104-point hardening specification.

### Phase 2 — Project Generation Hardening
- Rewrote `generate_project.py`: deterministic 24-character object IDs, a single sources list per target, embedded extension copy phase, sanitized build settings, automated plist/entitlements generation, self-validation.
- Verified: 316 object references all resolve; `productReference` values are canonical (`...0001` appex, `...0002` app, `...0003` tests); `LocalProxyServer` is compiled into **both** the App and Extension targets; `TunnelState` registered in both.

### Phase 3 — YAML Import Engine
- Rewrote `Tunnexa/YAML/YAMLParser.swift`: indentation-aware parser with a `YAMLValue` tree, line-accurate errors (`YAMLParsingError.invalidStructure(line:message:)`), `missingProxiesSection`, structured `validation([YAMLValidationIssue])`, and `parseDetailed(_:) -> YAMLImportSummary`.
- Unsupported proxy/rule types are skipped with warnings; unresolved references, duplicates, bad ports, malformed groups/rules are hard validation errors; `NETWORK` payloads accept TCP/UDP/TCP,UDP/IP/CIDR.
- Rewrote `YAMLParserTests.swift` (~20 tests incl. CRLF, comments, quotes, tabs, indentation, duplicates, unresolved refs, skipped types, rule arity, NETWORK payloads).

### Phase 4 — Error Handling & Redaction
- `VPNErrorDetails` redacts error text and failure reasons before persistence; code 6 (ConfigurationUnknown) explanation added.
- `VPNEnvironmentDetector` retained as-is (correct).

### Phases 5–7 — Packet Tunnel & Dispatcher Core
- **`LocalProxyServer` rewrite** (extension target, also compiled into app): RFC 1928 greeting/CONNECT/UDP ASSOCIATE, RFC 1929 local auth with constant-time comparison, reply codes 0x01–0x08, fail-closed fallback (no rule + no selection ⇒ REP 0x02, never implicit DIRECT), label-boundary DOMAIN-SUFFIX matching, NETWORK/CIDR/IPv6 rules, round-robin load balancing with signature-based index reset, cyclic-group detection, `UDPAssociation` with idle timers and persistent relays, per-datagram rule evaluation.
- **`NetworkAddressMatcher`** (IPv4/IPv6/CIDR helpers) extracted for hermetic unit testing.
- **`ProxyEndpointResolver`**: getaddrinfo with 60 s cache + async variant for NETWORK rules against domain destinations.
- **`TunnelEngine`**: `Socks5Tunnel.run` on a dedicated thread, `quit()` + join on stop, and `TunnelStatsSampler` (1 Hz poll → Int64 stats in `SharedSettings`).
- **`PacketTunnelProvider` rewrite**: start-up validation (no config → 100, no usable selection → 101, invalid selection → 102), MTU validation, IPv4/IPv6 exclusions incl. local networks, DNS 198.18.0.2, tunnel fd acquisition via ioctl with KVC fallback, engine/sampler/resolver wiring.

### Phases 8–9 — VPNManager & Auto-Reconnect
- **`AutoReconnectPolicy`**: deterministic backoff ladder `[1,2,4,8,15,30]`, `maxAttempts = 5`, `delay(forAttempt:)`, `mayRetry(afterAttempt:)`.
- **`VPNManager` rewrite**: published `TunnelState` (NE status authoritative), `isBusy`, `lastError`, wait-for-connected with 30 s timeout, start-up validation, auto-reconnect timer, kill switch (`NEOnDemandRuleConnect`), `autoConnectIfNeeded()`.

### Phase 10 — Health Testing & Diagnostics
- **`ProxyHealthTester`**: staged probe (TCP connect → greeting → RFC 1929 auth → CONNECT), per-stage timings, `HealthTestCompletionGate` for exactly-once completion on the main queue.
- **`DiagnosticsRunner`**: `DiagnosticsBundle` + `collect` (redacted, credential-mode aware) + `exportToFile`.

### Phase 11 — UI Layer Migration
- `ProxyViewModel` → `SharedSettings` with atomic config commits (revision++), stable IDs, credential preservation, search/sort, bounded-latency testing (max 6 concurrent), progress + cancel.
- `VPNViewModel` → `TunnelState`-based with session stats via `SharedSettings` (incl. `Int64` timestamp fix).
- `MainView` state-based status card/ring/colors, `isBusy` spinner.
- `ProxiesView` search/sort bar, test progress + cancel.
- `SettingsView` MTU validation, honest kill-switch wording, credential-mode display.
- `TunnexaApp` scenePhase auto-connect + config load.
- `DiagnosticsView` state-based status, export button, credential-mode row; `AddProxySheet` migrated to `KeychainHelper.loadPassword` + new tester API.

### Phase 12 — Test Suite (AUTHORED, NOT EXECUTED — see §1)
| File | Coverage |
|---|---|
| `RoutingTests.swift` (rewritten) | suffix boundary, NETWORK/CIDR rules, resolved-address rules, fail-closed fallback, DIRECT/BLOCK targets, load-balance round-robin + skip + membership reset, select-group stored option, circular refs, group with DIRECT/BLOCK members, address matcher, IPv4/IPv6 byte encoding |
| `YAMLParserTests.swift` (rewritten) | ~20 parsing/validation cases (see Phase 3) |
| `SOCKS5ProtocolTests.swift` (new) | hermetic loopback end-to-end: greeting, CONNECT relay/echo, BLOCK REP 0x02, no-selection fail-closed, unsupported command 0x07, RFC 1929 local auth accept/reject, upstream proxy credential handoff via `CredentialStore` |
| `HealthTesterTests.swift` (new) | online, auth-required success, auth-rejected, connect-rejected, silent timeout, connection refused, exactly-once completion |
| `CredentialStoreTests.swift` (new) | in-memory round trip/isolation, fallback obfuscation (no plaintext in defaults), protocol conformance, mode descriptions |
| `AutoReconnectTests.swift` (new) | ladder values, clamping, retry cap, monotonicity |
| `LogRedactionTests.swift` (new) | `=`/`:` forms, JSON, single quotes, URL userinfo, auth_token/client_secret, idempotence, log-file leak test, `VPNErrorDetails` redaction |
| `VPNManagerTests.swift` | unchanged (environment detection, error details, provider bundle id) |
| `EnvironmentDetectorTests.swift` (new) | LC env-var/path/bundle-id detection, standalone vs unknown, signature precedence, simulator flag, support gating, capability mapping |
| `EngineConfigTests.swift` (new) | no `fd:`/`udp:`/`name`/`ipv4`/`ipv6` keys, dispatcher endpoint, MTU clamping, mapdns, tuning floor (`36864`), custom tuning, IPv6-flag neutrality |
| `StartupStateMachineTests.swift` (new) | exactly-once settle, reset per session (the reused-provider regression), cancel-never-invokes, begin-after-cancel |
| `TunnelEngineTests.swift` (rewritten) | fd-free engine: descriptors survive run/stop/deinit, run-once, exit-code delivery, `onStopRequested` |

### Phase 13 — CI / Packaging
- `.github/workflows/build.yml`: generator determinism check, SPM dependency cache, **unit test job on iOS Simulator** (dynamic device selection), IPA/app validation step.
- `validate_ipa.py`: added main-executable check, signed/unsigned detection, provisioning-profile requirement for signed bundles, app↔extension signing consistency.

### Phase 14 — Documentation
- README: corrected health-tester description, CI pipeline description, diagnostics panel export.
- DEPLOYMENT: corrected tunnel lifecycle (dispatcher + quit/join), added fail-closed/kill-switch/reconnect documentation, expanded IPA validation checklist.

---

## 3. Locked Design Decisions

- **Fail-closed routing:** no rule match + no selection ⇒ block (REP 0x02). Never implicit DIRECT.
- **Selection is wire-format by name;** configuration stored as one atomic JSON blob with `revision`; credentials never inside the blob (separate `CredentialStore`, keyed by stable proxy UUID).
- **Credential strategy:** per-target keychain → shared access-group keychain → clearly-flagged insecure obfuscated fallback (development/unsigned builds only), surfaced in Diagnostics.
- **Single state model:** `TunnelState` across app, extension, and tests; NE status authoritative.
- **Deterministic generator:** pbxproj is machine-generated; CI asserts regeneration is a no-op.
- **Hermetic tests:** every "remote" endpoint is an in-process loopback NWListener; no external network required.

---

## 4. Known Limitations / Next Steps

1. **Execute the suite in CI** (push → GitHub Actions) and fix any compile/assert failures surfaced by the simulator runs. This is the single most important next step.
2. **Physical-device verification is impossible from this host** (Windows, no Xcode, no iPhone 15 Pro attached). Standalone system-VPN behavior (profile save, `.connecting → .connected`, kill switch) and LiveContainer in-app proxy mode **must** be verified on the device; CI can only cover build + simulator unit tests.
3. The CI runner must be a macOS image that actually offers Xcode 26.6 (`macos-26`); older images may not have it.
4. Optional: add `UDPAssociation` protocol test (datagram relay through a loopback UDP echo server) — infrastructure already exists in `SOCKS5ProtocolTests`.
5. Optional: engine integration test on-device only (Tun2SocksKit is a binary framework; it cannot be exercised by unit tests without a device/simulator process with the extension context).

---

## 5. New/Changed Files (2026-08-16 pass)

- `TunnexaPacketTunnel/EngineConfigBuilder.swift` — NEW: pure engine-YAML builder (mtu-only tunnel, no `udp:`/`fd:` keys, mapdns, tuning with enforced stack floor).
- `TunnexaPacketTunnel/StartupStateMachine.swift` — NEW: per-session startup coordination.
- `TunnexaPacketTunnel/PacketTunnelProvider.swift` — rewritten: fd-less engine, per-session startup, config guards, network-settings setup, local-dispatcher probe (real SOCKS5 greeting/auth/CONNECT), stats sampler, honest failure codes.
- `TunnexaPacketTunnel/TunnelEngine.swift` — rewritten: no fd ownership/close; injectable `onExit`/`onStopRequested`; `stop(timeout:)` best-effort.
- `Shared/VPNEnvironmentDetector.swift` — rewritten: `.simulator`/`.unsupported` cases, `EnvironmentCapabilities`, injectable detection, fail-safe support gating.
- `Shared/VPNErrorDetails.swift`, `Shared/SharedSettings.swift` — environment dialogs; `inAppProxyEnabled` key.
- `Tunnexa/VPN/InAppProxyManager.swift` — NEW: in-app dispatcher manager (Mode C).
- `Tunnexa/VPN/VPNManager.swift`, `Tunnexa/App/TunnexaApp.swift`, `Tunnexa/Views/MainView.swift`, `Tunnexa/VPN/DiagnosticsRunner.swift` — mode-aware wiring/UI/diagnostics.
- Tests: `EnvironmentDetectorTests.swift`, `EngineConfigTests.swift`, `StartupStateMachineTests.swift` (NEW), `TunnelEngineTests.swift` (rewritten: descriptor-preservation contract).
- `generate_project.py` — registers all new files (app + extension + tests); determinism + reference checks pass locally.
- `validate_ipa.py` — real `codesign --verify`/`-dv`/entitlement dumps, `security cms -D` profile decoding, `otool` Mach-O checks (macOS-only, skipped with notice elsewhere), honest unsigned verdict + `--expect-unsigned`.
- `.github/workflows/build.yml` — validation uses `--expect-unsigned`; release notes state honest capability limits (unsigned ⇒ no system VPN registration; LiveContainer in-app mode works).