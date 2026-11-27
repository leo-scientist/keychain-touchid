import Darwin

/// Whether a file or directory can be changed by root only. What the tool trusts on disk — its settings and
/// the build that replaces it — must be out of reach of a process that merely runs as the user.
enum RootOwned {
    enum Problem: Equatable {
        case wrongType
        case wrongOwner
        case writableByOthers
    }

    /// - Parameter type: `S_IFREG` or `S_IFDIR`; anything else, such as a symbolic link, is a problem.
    static func problem(owner: uid_t, mode: mode_t, type: mode_t, requiredOwner: uid_t = 0) -> Problem? {
        guard mode & S_IFMT == type else {
            return .wrongType
        }

        guard owner == requiredOwner else {
            return .wrongOwner
        }

        guard mode & (S_IWGRP | S_IWOTH) == 0 else {
            return .writableByOthers
        }

        return nil
    }
}
