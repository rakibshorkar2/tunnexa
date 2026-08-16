import Foundation

/// Builds the YAML configuration for the hev-socks5-tunnel engine
/// (embedded via the Tun2SocksKit package).
///
/// Engine contract (verified against hev-socks5-tunnel 2.17.1 config parser):
///  - The `tunnel` section does NOT support an `fd` key. The engine receives
///    the TUN descriptor directly from `hev_socks5_tunnel_main(path, fd)`;
///    Tun2SocksKit's `Socks5Tunnel.run(withConfig:)` discovers the packet
///    flow's descriptor itself (getpeername scan). No descriptor may ever be
///    closed by this process — it is owned by `NEPacketTunnelFlow`.
///  - With an external descriptor the engine only consumes `tunnel.mtu`
///    (lwIP read buffer size). `name`, `ipv4` and `ipv6` are ignored in that
///    mode and are therefore not emitted.
///  - `socks5.udp` must be ABSENT: `udp: udp` switches hev into UDP-in-UDP
///    mode (raw datagrams to the SOCKS5 address). The local dispatcher only
///    implements standard SOCKS5 UDP ASSOCIATE, so UDP-in-UDP would black-hole
///    every UDP session. With the key absent, hev uses UDP ASSOCIATE, which
///    the dispatcher supports end to end.
///  - `misc.task-stack-size` is silently raised by the engine to
///    `TASK_STACK_SIZE (20480) + max(tcp-buffer-size, UDP_BUF_SIZE (1500) *
///    udp-copy-buffer-nums)`. Requesting 20480 while keeping the defaults
///    (tcp-buffer-size 65536, udp-copy-buffer-nums 10) wastes ~65 KB of stack
///    per session. This builder bounds both so the stack request actually
///    takes effect and caps concurrent sessions to bound extension memory.
public struct EngineConfigBuilder {

    public struct Tuning {
        /// Per-session task stack (bytes). The engine enforces a floor of
        /// `20480 + max(tcpBufferSize, 1500 * udpCopyBufferNums)`.
        public var taskStackSize: Int = 20480
        /// lwIP TCP send buffer per session (bytes).
        public var tcpBufferSize: Int = 16384
        /// lwIP UDP copy buffers per session.
        public var udpCopyBufferNums: Int = 2
        /// Hard cap on concurrent sessions (0 = unlimited).
        public var maxSessionCount: Int = 256
        /// Upstream connect timeout (ms).
        public var connectTimeoutMs: Int = 5000
        /// TCP/read-write timeout (ms).
        public var readWriteTimeoutMs: Int = 60000
        /// Engine log level: debug / info / warn / error.
        public var logLevel: String = "warn"

        public init() {}

        /// The stack size the engine will actually use, given the buffer
        /// choices above.
        public var effectiveTaskStackSize: Int {
            let engineFloor = 20480 + max(tcpBufferSize, 1500 * udpCopyBufferNums)
            return max(taskStackSize, engineFloor)
        }
    }

    /// Builds the engine configuration string.
    public static func build(mtu: Int, isIPv6Enabled: Bool, localPort: UInt16, tuning: Tuning = Tuning()) -> String {
        let clampedMtu = min(max(mtu, MTULimit.minimum), MTULimit.maximum)
        let clampedPort = min(max(Int(localPort), 1), 65535)
        let stackSize = tuning.effectiveTaskStackSize

        var yaml = """
        tunnel:
          mtu: \(clampedMtu)
        socks5:
          address: 127.0.0.1
          port: \(clampedPort)
        mapdns:
          address: \(AppConfigConstants.dnsIPv4)
          port: 53
          network: 100.64.0.0
          netmask: 255.192.0.0
          cache-size: 10000
        misc:
          task-stack-size: \(stackSize)
          tcp-buffer-size: \(tuning.tcpBufferSize)
          udp-copy-buffer-nums: \(tuning.udpCopyBufferNums)
          max-session-count: \(tuning.maxSessionCount)
          connect-timeout: \(tuning.connectTimeoutMs)
          read-write-timeout: \(tuning.readWriteTimeoutMs)
          log-file: stderr
          log-level: \(tuning.logLevel)
        """
        return yaml
    }
}