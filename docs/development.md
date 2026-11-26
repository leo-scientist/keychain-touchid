# Development

Working on the tool itself. For installing it see [installation.md](installation.md).

## Layout

```
Sources/keychain_touchid/      the tool; one file per responsibility, see INDEX.md
Tests/keychain_touchidTests/   one test file per source file, plus TestSupport.swift
Makefile                       build, test, sign, install, verify, uninstall
keychain-touchid.conf.sample   settings file with every setting commented out
docs/                          this documentation
```

The package has no dependencies. It is one executable target and one test
target.

## Building and testing

```sh
make build   # release binary in .build/release/
make test    # the whole suite
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

- **Command flows** (`CommandsTests`) run the real `Commands` over fakes for the
  Keychain store and the authenticator. This is where the central properties
  are proven: a refused authentication never reaches the Keychain, a missing
  item never prompts, a reuse does not extend the window.
- **Keychain code** (`KeychainStoreTests`, `AuthCacheTests`) runs against a
  throwaway keychain file created for each test and deleted afterwards. It is
  never added to the user's keychain search list, and user interaction is off,
  so a test can neither touch the login keychain nor show a dialog.
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
  `AuthenticationError`, `SettingsError`); `Failure` maps them to exit codes in
  one place.
- The security rules in [security.md](security.md#rules-for-changing-the-code).

## Acceptance checklist

Run with the installed binary and a test item, here `kt-accept`. Automated tests
do not cover any of this.

### Every read asks

| # | Action | Expected |
| --- | --- | --- |
| A1 | `printf 'value-1' \| keychain-touchid set kt-accept "$USER"` | Exit 0; Keychain Access shows the kind `keychain-touchid secret` |
| A2 | `keychain-touchid get kt-accept "$USER"`, twice | A dialog each time, naming the item and the process; prints `value-1` |
| A3 | The same, then Cancel | Exit 3, nothing on stdout |
| A4 | In the dialog choose the password instead of Touch ID | Works with the Mac password |
| A5 | `security find-generic-password -s kt-accept -a "$USER" -w` | The macOS password prompt; press Deny; no value |
| A6 | `DYLD_INSERT_LIBRARIES=<a test dylib> keychain-touchid get …`; `lldb -p <pid>` | The dylib is not loaded; the debugger cannot attach |
| A7 | `keychain-touchid set kt-accept "$USER"` in a terminal, Ctrl+C at the prompt | `stty -a` still shows `echo`; the old value is intact |
| A8 | A 4000-character secret through a pipe, then `get \| wc -c` | The same length |
| A9 | `set` over the existing item, then `get` | The new value; no Mac password prompt |
| A10 | Change the code, `make update`, `get`, Always Allow, `get` again | One Mac password prompt for the new build, then Touch ID only |
| A11 | `security add-generic-password -s kt-foreign -a "$USER" -w x`, then `set`, `get`, `list` on it | `set` refuses with a hint, `get` exits 4, `list` does not show it |
| A12 | `keychain-touchid list` | Shows `kt-accept`; no dialog |
| A13 | `keychain-touchid delete kt-accept "$USER"`, then `get` | Exit 0, then exit 4 without a dialog |

Afterwards remove `kt-foreign` with `security delete-generic-password`.

### Reuse window

| # | Action | Expected |
| --- | --- | --- |
| B1 | No settings file; `get` twice | A dialog each time |
| B2 | `cache_seconds = 60`; `get` twice in one tab | No dialog the second time; a line on stderr about the reuse |
| B3 | Straight away, `get` in another tab | A dialog |
| B4 | `get` after more than 60 seconds | A dialog |
| B5 | `set` a new value, then `get` within the window | A dialog |
| B6 | `get --no-cache` within the window | A dialog |
| B7 | `get` from a process without a terminal (`osascript -e 'do shell script "…"'`) within the window | A dialog |
| B8 | `sudo chown "$USER"` on the settings file, then `get` | Exit 1 with an explanation; `make verify` fails |
| B9 | `policy = biometry`, then `get` | The dialog offers no password |
| B10 | An unknown setting in the file | Exit 1 |

### Not verified yet

These rest on documented macOS behaviour and have not been observed with this
tool:

- the exact sentence the authentication dialog shows around the reason text;
- behaviour in a remote (SSH) session;
- the hidden prompt refusing an entry that fills the terminal line;
- "Always Allow" adding a rebuilt binary to an item's trust list (A10);
- a debugger being refused (A6).
