import Foundation

/// Backoff schedule for automatic reconnection attempts.
///
/// The policy is deliberately simple and deterministic so it can be unit
/// tested: fixed delay ladder (1, 2, 4, 8, 15, 30 s), optional jitter for
/// production use, and a hard cap on the number of consecutive attempts. The
/// caller owns the timer; this type only answers "how long to wait" and "may I
/// try again".
public enum AutoReconnectPolicy {

    /// Delay ladder, index 0 = first retry.
    public static let backoffDelays: [TimeInterval] = [1, 2, 4, 8, 15, 30]

    /// Maximum consecutive auto-reconnect attempts before giving up until the
    /// user (or a status transition) resets the counter.
    public static let maxAttempts = 5

    /// Default jitter fraction applied on top of the ladder delay in
    /// production (spreads reconnect storms across clients).
    public static let defaultJitterFraction: Double = 0.25

    /// Delay before the `attempt`-th retry (1-based). Returns 0 for attempt 0
    /// and the final ladder value for attempts beyond the ladder length.
    public static func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        let index = min(attempt - 1, backoffDelays.count - 1)
        return backoffDelays[max(0, index)]
    }

    /// Jittered delay for the `attempt`-th retry.
    ///
    /// `random` must return a value in `[0, 1)`. `jitterFraction` of the base
    /// delay is subtracted from it, so the result stays within
    /// `[base * (1 - fraction), base]`. Deterministic when `random` is
    /// injected, so tests can verify the bounds.
    public static func jitteredDelay(forAttempt attempt: Int, jitterFraction: Double = defaultJitterFraction, random: () -> Double = { Double.random(in: 0..<1) }) -> TimeInterval {
        let base = delay(forAttempt: attempt)
        guard base > 0 else { return 0 }
        let fraction = min(max(jitterFraction, 0.0), 0.5)
        let spread = base * fraction
        let factor = random()
        return base - spread * factor
    }

    public static func mayRetry(afterAttempt attempt: Int) -> Bool {
        return attempt < maxAttempts
    }
}