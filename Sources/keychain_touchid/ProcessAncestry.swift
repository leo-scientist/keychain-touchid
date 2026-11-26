import Darwin

/// What the kernel reports about one process.
struct ProcessSnapshot: Equatable {
    /// Unavailable for some processes; `command` is the fallback.
    let executablePath: String?
    /// The kernel's short name for the process.
    let command: String

    var name: String {
        executablePath?.split(separator: "/").last.map(String.init) ?? command
    }

    /// The outermost application bundle the executable sits in, without the `.app` suffix.
    var applicationName: String? {
        guard let components = executablePath?.split(separator: "/"),
              let index = components.indices.dropLast().first(where: { index in
                  components[index].hasSuffix(Self.bundleSuffix) && components[index + 1] == "Contents"
              })
        else {
            return nil
        }

        return String(components[index].dropLast(Self.bundleSuffix.count))
    }

    private static let bundleSuffix = ".app"
}

/// Reads processes and their parents from the kernel. See docs/authentication.md#the-requesting-process.
enum ProcessAncestry {
    private static let maxDepth = 32

    /// The process `pid` and its ancestors, nearest first, stopping before launchd.
    static func chain(from pid: pid_t) -> [ProcessSnapshot] {
        var chain = [ProcessSnapshot]()
        var current = pid

        while current > 1, chain.count < maxDepth, let info = info(of: current) {
            chain.append(ProcessSnapshot(executablePath: executablePath(of: current), command: command(of: info)))
            current = info.kp_eproc.e_ppid
        }

        return chain
    }

    /// Uses `sysctl` because `proc_pidinfo` refuses to describe another user's process, such as root's
    /// `login`, which leads a terminal session and sits between a shell and its terminal application.
    static func info(of pid: pid_t) -> kinfo_proc? {
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size

        // A process that does not exist is reported as success with nothing written.
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        return info
    }

    /// The arguments a process was started with. Empty for another user's process: the kernel keeps those private.
    static func arguments(of pid: pid_t) -> [String] {
        var limit: Int32 = 0
        var limitSize = MemoryLayout<Int32>.size
        var limitName = [CTL_KERN, KERN_ARGMAX]

        guard sysctl(&limitName, UInt32(limitName.count), &limit, &limitSize, nil, 0) == 0, limit > 0 else {
            return []
        }

        var buffer = [UInt8](repeating: 0, count: Int(limit))
        var size = buffer.count
        var name = [CTL_KERN, KERN_PROCARGS2, pid]
        let countSize = MemoryLayout<Int32>.size

        guard sysctl(&name, UInt32(name.count), &buffer, &size, nil, 0) == 0, size > countSize else {
            return []
        }

        // Layout: the argument count, the executable path padded with zero bytes, then each argument
        // followed by a zero byte.
        let count = buffer.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        let afterCount = buffer[countSize..<size]

        guard count > 0, let pathEnd = afterCount.firstIndex(of: 0) else {
            return []
        }

        return afterCount[pathEnd...].drop { $0 == 0 }
            .split(separator: 0, maxSplits: count, omittingEmptySubsequences: false)
            .prefix(count)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))

        guard length > 0 else {
            return nil
        }

        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private static func command(of info: kinfo_proc) -> String {
        withUnsafeBytes(of: info.kp_proc.p_comm) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
