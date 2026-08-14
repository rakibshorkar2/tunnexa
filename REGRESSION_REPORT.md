# Tunnexa — Hardening & Regression Report

**Project:** Tunnexa — system-wide SOCKS5 VPN for iOS
**Status:** All 14 hardening phases implemented. Swift sources and tests finalized; **tests authored but not executed locally** (see Execution Note).
**Date:** 2026-08-14

---

## 1. Execution Note (IMPORTANT)

This project was hardened on a **Windows host with no Xcode toolchain**. Consequently:

- All Swift code and tests were **authored and reviewed statically** against the real APIs in this repository.
- **No unit tests were compiled or executed locally.**
- The only executable validation performed locally was Python-based:
  - `generate_project.py` — pbxproj regeneration, reference integrity (`[ OK ] All pbxproj object references resolve.`), and determinism (`[ OK ] Generator is deterministic.`).
  - `validate_ipa.py` — syntax/smoke check.
- **The execution venue for the Swift test suite is the GitHub Actions workflow** (`.github/workflows/build.yml`), which now runs `xcodebuild test` on an iOS Simulator on every push. The first green CI run is the authoritative verification of the suite.

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
2. Optional: add `UDPAssociation` protocol test (datagram relay through a loopback UDP echo server) — infrastructure already exists in `SOCKS5ProtocolTests`.
3. Optional: on-device verification of profile save / kill switch behaviour on a standalone install (TrollStore or signed), which no test can cover.