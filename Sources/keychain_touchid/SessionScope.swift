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

        guard sessionID > 0, let own = processInfo(of: getpid()), let leader = processInfo(of: sessionID) else {
            return nil
        }

        return SessionScope(
            sessionID: sessionID,
            leaderStartedAt: UInt64(clamping: leader.kp_proc.p_starttime.tv_sec),
            terminal: UInt32(bitPattern: own.kp_eproc.e_tdev)
        )
    }

    /// Uses `sysctl` because the leader of a terminal session is usually root's `login`, and `proc_pidinfo`
    /// refuses to describe another user's process.
    static func processInfo(of pid: pid_t) -> kinfo_proc? {
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size

        // A process that does not exist is reported as success with nothing written.
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        return info
    }
}
