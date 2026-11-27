# Roadmap

What the project intends to do until the end of 2027, and what it will not do.
The tool is meant to stay small: the less it does, the easier it is to check.

## Planned

- **Keep up with macOS and Swift.** Build, test and run CI on each new macOS
  and Swift release, and fix what they break.
- **Replace the deprecated `SecKeychain…` calls** once Apple offers a
  replacement that keeps the same guarantees without a paid developer account
  ([keychain.md](docs/keychain.md#why-the-file-based-keychain)).
- **Fix reported bugs and vulnerabilities**, each with a test, as
  [SECURITY.md](SECURITY.md) and [CONTRIBUTING.md](CONTRIBUTING.md) describe.
- **Keep the supply chain checked**: actions pinned by commit and updated by
  Dependabot, CodeQL, OpenSSF Scorecard, signed release tags.

## Considered, if asked for

- Shell completion for bash and fish.

## Not planned

- A graphical interface, a background service or a daemon.
- Anything over the network: syncing, sharing, remote access.
- Other platforms or secret stores than the macOS login Keychain.
- Installation through a package manager whose prefix the user can write to
  ([installation.md](docs/installation.md#requirements)).
- Options that weaken or skip authentication
  ([security.md](docs/security.md#rules-for-changing-the-code)).
