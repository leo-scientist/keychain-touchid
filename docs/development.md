# Development

Working on the tool itself. For installing it see [installation.md](installation.md).

## Layout

```
Sources/keychain_touchid/      the tool; one file per responsibility, see INDEX.md
Tests/keychain_touchidTests/   one test file per source file, plus TestSupport.swift
Makefile                       build, test, lint, sign, install, verify, uninstall
keytap.conf.sample             settings file with every setting commented out
completions/_keytap            zsh completion
docs/                          this documentation
.github/                       CI workflow, Dependabot, issue and pull request templates
.swift-format                  formatter configuration
```

The package has no dependencies. It is one executable target and one test
target.

## Building and testing

```sh
make build    # release binary in .build/release/
make test     # the whole suite
make lint     # formatting and style, strict
make format   # fixes what lint reports, in place
make smoke    # runs the built binary: help, version, usage errors
```

CI (`.github/workflows/ci.yml`) runs `make lint`, `make test` and `make smoke`
on every push to `main` and every pull request.

`swift format` comes with the toolchain; `.swift-format` holds the few settings
that differ from its defaults. The formatter has the last word on layout.

`make smoke` covers what the unit tests cannot reach: the entry point and exit
codes of the real binary. It stays away from the Keychain and the settings file,
so it runs anywhere, CI included. It also checks that the version the binary
prints has an entry in `CHANGELOG.md`.

To run one suite or test, pass the plugin path yourself:

```sh
P="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
swift test -Xswiftc -plugin-path -Xswiftc "$P" --filter CommandsTests
```

Use `make test` rather than `swift test`. With only the Command Line Tools
installed, SwiftPM does not find the Swift Testing macro plugin by itself; the
Makefile passes its location when the directory exists.

The build prints deprecation warnings for a few `SecKeychain…` calls. They are
expected ([keychain.md](keychain.md#why-the-file-based-keychain)).

A development build (`swift build`, `swift run`) is a different program to the
Keychain than the installed one and has no hardened runtime. Do not point it at
real secrets, and never let the Keychain "Always Allow" it.

## How the code is tested

- **Command flows** (`CommandsTests`, `HandoverTests`) run the real flows over
  fakes for the Keychain store, the authenticator and the successor build. This
  is where the central properties are proven: a refused authentication never
  reaches the Keychain, a missing item never prompts, a reuse does not extend
  the window, an item planted during a hand-over never receives the secret, and
  a failed hand-over takes every secret back.
- **Keychain code** (`KeychainStoreTests`, `AuthCacheTests`) runs against a
  throwaway keychain file created for each test and deleted afterwards. It is
  never added to the user's keychain search list, so a test cannot touch the
  login keychain. Keychain user interaction is switched off for the whole test
  process and never back on, so no test can show a dialog; for the same reason
  no test reads from a keychain it has locked. Such a keychain has no partition
  list, so these tests do not show what happens between different programs on
  the login keychain; that was checked by hand and is recorded in
  [keychain.md](keychain.md#what-another-program-can-do).
- **Pure logic** — argument parsing, input normalisation, settings parsing and
  trust checks, display sanitizing, error-to-exit-code mapping — is tested
  directly.

What automated tests cannot cover is the authentication dialog, the hidden
prompt and the installation. Those are in the checklist below.

To run the suite with a controlling terminal, which exercises the other branch
of the session-scope test, run `make test` from a terminal tab.

## Conventions

- Immutable values; new collections instead of mutation, except for local
  accumulation.
- A blank line around every compound statement and before `return`.
- Comments say only what the code cannot: a reason, a contract, a trap. Detail
  lives in these documents, and the code points here.
- Errors are specific types per part (`UsageError`, `InputError`, `StoreError`,
  `AuthenticationError`, `SettingsError`, `HandoverError`); `Failure` maps them
  to exit codes in one place.
- The security rules in [security.md](security.md#rules-for-changing-the-code).
- A change of behaviour gets a line under *Unreleased* in `CHANGELOG.md`.

## Releasing

1. Set `version` in `Main.swift`.
2. In `CHANGELOG.md`, turn *Unreleased* into a section for that version and
   date, and add an empty *Unreleased* above it. `make smoke` fails until the
   two agree.
3. Commit, then tag the commit with the version (`0.2.0`) and push the tag.

## Acceptance checklist

Run with the installed binary and a test item, here `kt-accept`. Automated tests
do not cover any of this.

### Every read asks

| # | Action | Expected |
| --- | --- | --- |
| A1 | `printf 'value-1' \| keytap set kt-accept "$USER"` | Exit 0; Keychain Access shows the kind `keychain-touchid secret` |
| A2 | `keytap get kt-accept "$USER"`, twice | A dialog each time, naming the item, the requester and the application; prints `value-1` |
| A3 | The same, then Deny | Exit 3, nothing on stdout |
| A4 | In the dialog choose the password instead of Touch ID | Works with the Mac password |
| A5 | `security find-generic-password -s kt-accept -a "$USER" -w` | The macOS password prompt; press Deny; no value |
| A6 | `DYLD_INSERT_LIBRARIES=<a test dylib> keytap get …`; `lldb -p <pid>` | The dylib is not loaded; the debugger cannot attach |
| A7 | `keytap set kt-accept "$USER"` in a terminal, Ctrl+C at the prompt | `stty -a` still shows `echo`; the old value is intact |
| A8 | A 4000-character secret through a pipe, then `get \| wc -c` | The same length |
| A9 | `set` over the existing item, then `get` | The new value; no Mac password prompt |
| A10 | With two secrets stored: change the code, `make update`, then `get` each secret | One `sudo` password and one Touch ID dialog that says both secrets are handed to the new build; afterwards each `get` asks for Touch ID only, never for the Mac password |
| A11 | `security add-generic-password -s kt-foreign -a "$USER" -w x`, then `set`, `get`, `list` on it | `set` refuses with a hint, `get` exits 4, `list` does not show it |
| A12 | `keytap list` | Shows `kt-accept`; no dialog |
| A13 | `keytap delete kt-accept "$USER"`, then `get` | Exit 0, then exit 4 without a dialog |
| A14 | `get` from a script, from an editor's terminal, and from inside `tmux` | The dialog shows the script's name, `running in` the editor, `started by tmux` |
| A15 | `security add-generic-password -D "keychain-touchid secret" -s kt-planted -a "$USER" -w x`, then `printf v \| keytap set kt-planted "$USER"`, then `get` | `set` reports `updated …`; `get` asks for Touch ID only and prints `v` |
| A16 | `security lock-keychain`, then `printf v2 \| keytap set kt-accept "$USER"`; unlock, then `get` | `set` exits 1 saying the keychain is locked; `get` prints the old value |
| A17 | `HOME=/nonexistent keytap list` | The same list as without it |
| A18 | In a new zsh tab: `keytap get <Tab>`, then `keytap get kt-accept <Tab>` | The stored services, then the accounts of `kt-accept`; no dialog |
| A19 | Change the code, `make update`, cancel the Touch ID dialog | `make` says the update was stopped; `/usr/local/bin/keytap.new` is gone; `get` asks for Touch ID only |
| A20 | Change the code, `make update`, press Ctrl+C at the Touch ID dialog, then confirm | Ctrl+C does nothing; the secrets move, the new build is installed, then `make` stops; `make verify` passes; `get` asks for Touch ID only |
| A21 | `make purge`, answer anything but `delete` | `Nothing was removed.`; `keytap list` is unchanged |
| A22 | With only test items stored, one of them `printf v \| keytap set 'kt\tback' "$USER"`: `make purge`, answer `delete` | The list shows `kt\tback` as typed; every item is reported `removed`; `keytap list` prints nothing |

Afterwards remove `kt-foreign` with `security delete-generic-password`.

### Reuse window

| # | Action | Expected |
| --- | --- | --- |
| B1 | No settings file; `get` twice | A dialog each time |
| B2 | `cache_seconds = 60`; `get` twice in one tab | The dialog says the terminal may read again for 1 minute; no dialog the second time; a line on stderr about the reuse |
| B3 | Straight away, `get` in another tab | A dialog |
| B4 | `get` after more than 60 seconds | A dialog |
| B5 | `set` a new value, then `get` within the window | A dialog |
| B6 | `get --no-cache` within the window | A dialog |
| B7 | `get` from a process without a terminal (`osascript -e 'do shell script "…"'`) within the window | A dialog |
| B8 | `sudo chown "$USER"` on the settings file, then `get` | Exit 1 with an explanation; `make verify` fails |
| B9 | `policy = biometry`, then `get` | The dialog offers no password |
| B10 | An unknown setting in the file | Exit 1 |
