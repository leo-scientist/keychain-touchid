# Changelog

Notable changes, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
versions follow [Semantic Versioning](https://semver.org/). `keytap --version` prints the installed one.

## [Unreleased]

### Added

- OpenSSF Scorecard: a weekly supply-chain check with its results behind a badge in the README.
- CodeQL analysis of the Swift code and the workflows.
- OpenSSF Best Practices badge (passing level) in the README.
- `make install DESTDIR=<dir>` stages the files under `<dir>` for a package, without `sudo` or a hand-over.
- `CODE_OF_CONDUCT.md`, `GOVERNANCE.md` and `ROADMAP.md`.
- An assurance case in `docs/security.md`, and how to reproduce a build bit for bit in `docs/development.md`.

### Changed

- `SECURITY.md` links straight to private vulnerability reporting and describes each step from report to disclosure.
- Release tags are signed with GPG from the next release on; `docs/installation.md` says how to check one.
- Contributions need a DCO sign-off (`git commit -s`).

## [0.1.0] - 2026-11-27

First release. What it does is described in the [README](README.md).

[Unreleased]: https://github.com/leo-scientist/keychain-touchid/compare/0.1.0...HEAD
[0.1.0]: https://github.com/leo-scientist/keychain-touchid/releases/tag/0.1.0
