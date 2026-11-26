import Darwin

/// Identifies the terminal session a process belongs to, using only what the kernel reports.
/// See docs/reuse-window.md#session-scope.
struct SessionScope: Codable, Equatable {
    /// `e_tdev` of a process without a controlling terminal (NODEV).
    static let noTerminal = UInt32.max

    let sessionID: Int32
    /// Tells a session apart from a later one that got the same id.
    let leaderStartedAt: UInt64
    let terminal: UInt32

    init?(sessionID: Int32, leaderStartedAt: UInt64, terminal: UInt32) {
        guard terminal != Self.noTerminal else {
            return nil
        }

        self.sessionID = sessionID
        self.leaderStartedAt = leaderStartedAt
        self.terminal = terminal
    }

    static func current() -> SessionScope? {
        let sessionID = getsid(0)

        guard sessionID > 0,
              let own = ProcessAncestry.info(of: getpid()),
              let leader = ProcessAncestry.info(of: sessionID)
        else {
            return nil
        }

        return SessionScope(
            sessionID: sessionID,
            leaderStartedAt: UInt64(clamping: leader.kp_proc.p_starttime.tv_sec),
            terminal: UInt32(bitPattern: own.kp_eproc.e_tdev)
        )
    }
}
