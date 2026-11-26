import Foundation

struct Output {
    /// Standard output: secrets and listings only.
    let write: ([UInt8]) throws -> Void
    /// Standard error: everything meant for a person.
    let note: (String) -> Void
    let isTerminal: Bool
}

/// The flow of each command. See docs/commands.md.
struct Commands {
    let store: any SecretStore
    let authenticator: any Authenticator
    let requester: Requester
    let readSecret: (ItemID) throws -> [UInt8]
    let cache: AuthCache
    let output: Output

    func run(_ command: Command) async throws {
        switch command {
        case let .get(item, useCache):
            try await get(item, useCache: useCache)
        case let .set(item):
            try set(item)
        case let .delete(item):
            try delete(item)
        case let .list(service):
            try list(service: service)
        }
    }

    private func get(_ item: ItemID, useCache: Bool) async throws {
        // Checked first so that a missing item never costs the user an authentication prompt.
        guard try store.state(of: item) == .own else {
            throw StoreError.notFound
        }

        if useCache, let reused = try reusedAuthentication(for: item) {
            try emit(reused.secret)
            output.note("authentication reused from \(reused.age) s ago")

            return
        }

        try await authenticator.authenticate(reason: PromptText.reason(for: item, requester: requester))
        let secret = try store.read(item)
        try emit(secret)

        do {
            try cache.remember(secret, for: item)
        } catch {
            output.note("could not remember the authentication: \(Failure(error).message)")
        }
    }

    private func reusedAuthentication(for item: ItemID) throws -> (secret: [UInt8], age: Int)? {
        guard let record = cache.freshRecord(for: item) else {
            return nil
        }

        let secret = try store.read(item)

        guard AuthCache.covers(record, secret: secret) else {
            return nil
        }

        return (secret, cache.age(of: record))
    }

    private func set(_ item: ItemID) throws {
        // Decided before asking for the secret, so a refusal does not waste the user's input.
        let state = try store.state(of: item)

        guard state != .foreign else {
            throw StoreError.duplicateItem
        }

        let secret = try readSecret(item)

        if state == .own {
            try store.update(secret, of: item)
            output.note("updated “\(item.service)” (\(item.account))")
        } else {
            try store.add(secret, as: item)
            output.note("created “\(item.service)” (\(item.account))")
        }
    }

    private func delete(_ item: ItemID) throws {
        try store.delete(item)

        do {
            try cache.forget(item)
        } catch {
            output.note("could not remove the remembered authentication: \(Failure(error).message)")
        }
    }

    private func list(service: String?) throws {
        // Names come from the Keychain, where any process may have put them: one item must stay one line.
        let lines = try store.list(service: service).map { item in
            let service = DisplayText.sanitized(item.service, maxLength: Arguments.maxNameLength)
            let account = DisplayText.sanitized(item.account, maxLength: Arguments.maxNameLength)

            return "\(service)\t\(account)\n"
        }

        try output.write(Array(lines.joined().utf8))
    }

    private func emit(_ secret: [UInt8]) throws {
        try output.write(output.isTerminal ? secret + [UInt8(ascii: "\n")] : secret)
    }
}
