# Installation

Installing, updating and removing the tool. Code: `Makefile`.

## Requirements

- macOS 13 or later.
- A Swift 6.4 toolchain: Xcode or the Command Line Tools.
- `sudo`, because the binary and the settings file are owned by root.

## Commands

| Command | What it does |
| --- | --- |
| `make install` | Builds, signs, installs, then runs `make verify` |
| `make update` | The same; use it after changing the sources. It never fetches sources itself |
| `make verify` | Checks an installation |
| `make uninstall` | Removes the binary and the settings file |
| `make build` | Builds the release binary only |
| `make test` | Runs the tests |
| `make clean` | Removes build products |

## What `make install` does

1. Builds the release binary (`swift build -c release`).
2. Signs it ad hoc with the hardened runtime
   (`codesign --sign - --force --options runtime`).
3. Creates `/usr/local/bin` and `/usr/local/etc` if they do not exist.
4. Installs the binary as `/usr/local/bin/keychain-touchid`, owner
   `root:wheel`, mode `755`.
5. If there is no settings file, installs the commented sample as
   `/usr/local/etc/keychain-touchid.conf`, owner `root:wheel`, mode `644`. An
   existing file is left alone.
6. Runs `make verify`.

The paths are fixed. The location must be owned by root, and the settings path
is built into the binary.

## What `make verify` checks

- The binary exists, is owned by `root:wheel` and has mode `755`.
- `/usr/local/bin` is owned by root and not writable by others.
- The signature is valid and the hardened runtime is on.
- `keychain-touchid` found through `PATH` is the installed binary.
- The settings file, if present, is owned by root, not writable by group or
  others, and accepted by the tool.

## After a rebuild

The Keychain identifies the binary by its signature, and an ad-hoc signature
changes with every change of the code. To the Keychain a rebuilt binary is a
different program, so the first read of each secret asks for the Mac password
once. There are two ways to continue:

- Answer **Always Allow**. The new build is added to the item's trust list. The
  old build stays on it.
- `delete` the secret and `set` it again with the new build. The item then
  trusts the new build only.

Installing the same build again changes nothing.

Never answer **Always Allow** for any other program
([security.md](security.md#keychain-prompts)).

## Uninstalling

`make uninstall` prints the secrets that remain, then removes the binary and the
settings file. Secrets stay in the Keychain, where they can be read with the Mac
password in Keychain Access. To remove one:

```sh
security delete-generic-password -s <service> -a <account>
```
