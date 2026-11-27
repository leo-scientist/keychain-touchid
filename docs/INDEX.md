# Documentation

`README.md` is the short introduction. These documents hold the detail.

## Using the tool

| Document | What it covers |
| --- | --- |
| [commands.md](commands.md) | What each command does step by step: arguments, input, output, exit codes |
| [recipes.md](recipes.md) | Using a secret from scripts and other programs; moving an existing secret |
| [settings.md](settings.md) | The settings file: location, who may write it, format |
| [installation.md](installation.md) | Checking the sources, installing, updating, verifying, uninstalling, staging for a package; how an update keeps your secrets readable |

## How it works

| Document | What it covers |
| --- | --- |
| [keychain.md](keychain.md) | How secrets are stored, who can read them, own and foreign items |
| [authentication.md](authentication.md) | The authentication prompt: policy, wording, the requesting process |
| [reuse-window.md](reuse-window.md) | Remembering an authentication: session scope, record, validity |
| [security.md](security.md) | What is protected, by what, and what is not; the assurance case |

## Working on it

| Document | What it covers |
| --- | --- |
| [development.md](development.md) | Layout, tests, lint, CI, reproducible builds, conventions, releasing, acceptance checklist |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | What a pull request needs |
| [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) | How people taking part treat each other |
| [GOVERNANCE.md](../GOVERNANCE.md) | Roles, how decisions are made, continuity |
| [ROADMAP.md](../ROADMAP.md) | What is planned, and what is out of scope |
| [SECURITY.md](../SECURITY.md) | Reporting a vulnerability |
| [CHANGELOG.md](../CHANGELOG.md) | Changes per release |

## Where the logic lives

| Source file | Responsibility | Document |
| --- | --- | --- |
| `Main.swift` | Entry point: wires the parts together, turns an error into a message and an exit code | [commands.md](commands.md#a-run-from-start-to-end) |
| `Arguments.swift` | Parses the command line, validates names | [commands.md](commands.md#arguments) |
| `Commands.swift` | The flow of `get`, `set`, `delete`, `list`, `receive` | [commands.md](commands.md) |
| `SecretInput.swift` | Reads a secret from a pipe or a hidden prompt | [commands.md](commands.md#entering-a-secret) |
| `ExitCode.swift` | Exit codes and the message for every error | [commands.md](commands.md#exit-codes) |
| `KeychainStore.swift` | Keychain items: add, read, delete, list, remove any, replace, lock state, own or foreign | [keychain.md](keychain.md) |
| `Authenticator.swift` | The authentication prompt and the policy behind it | [authentication.md](authentication.md) |
| `Requester.swift` | What asked and where it was started, text safe to display, the prompt wording | [authentication.md](authentication.md#the-requesting-process) |
| `ProcessAncestry.swift` | Reads a process, its arguments and its ancestors from the kernel | [authentication.md](authentication.md#how-the-processes-are-read) |
| `AuthCache.swift` | The remembered authentication | [reuse-window.md](reuse-window.md) |
| `SessionScope.swift` | Which terminal session a process belongs to | [reuse-window.md](reuse-window.md#session-scope) |
| `Settings.swift` | Loads and checks the settings file | [settings.md](settings.md) |
| `Handover.swift` | Moves the secrets to the build that replaces this one | [installation.md](installation.md#updating) |
| `RootOwned.swift` | Whether a file can be changed by root only | [settings.md](settings.md#who-may-write-it) |
| `Makefile` | Build, test, lint, smoke, sign, install, stage, verify, uninstall | [installation.md](installation.md), [development.md](development.md#building-and-testing) |
| `completions/_keytap` | zsh completion | [installation.md](installation.md#shell-completion) |
