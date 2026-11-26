# Documentation

`README.md` is the short introduction. These documents hold the detail.

## Using the tool

| Document | What it covers |
| --- | --- |
| [commands.md](commands.md) | What each command does step by step: arguments, input, output, exit codes |
| [recipes.md](recipes.md) | Using a secret from scripts and other programs; moving an existing secret |
| [settings.md](settings.md) | The settings file: location, who may write it, format |
| [installation.md](installation.md) | Installing, updating, verifying, uninstalling; what changes after a rebuild |

## How it works

| Document | What it covers |
| --- | --- |
| [keychain.md](keychain.md) | How secrets are stored, who can read them, own and foreign items |
| [authentication.md](authentication.md) | The authentication prompt: policy, wording, the requesting process |
| [reuse-window.md](reuse-window.md) | Remembering an authentication: session scope, record, validity |
| [security.md](security.md) | What is protected, by what, and what is not |

## Working on it

| Document | What it covers |
| --- | --- |
| [development.md](development.md) | Layout, tests, conventions, acceptance checklist |

## Where the logic lives

| Source file | Responsibility | Document |
| --- | --- | --- |
| `Main.swift` | Entry point: wires the parts together, turns an error into a message and an exit code | [commands.md](commands.md#a-run-from-start-to-end) |
| `Arguments.swift` | Parses the command line, validates names | [commands.md](commands.md#arguments) |
| `Commands.swift` | The flow of `get`, `set`, `delete`, `list` | [commands.md](commands.md) |
| `SecretInput.swift` | Reads a secret from a pipe or a hidden prompt | [commands.md](commands.md#entering-a-secret) |
| `ExitCode.swift` | Exit codes and the message for every error | [commands.md](commands.md#exit-codes) |
| `KeychainStore.swift` | Keychain items: add, update, read, delete, list, own or foreign | [keychain.md](keychain.md) |
| `Authenticator.swift` | The authentication prompt and the policy behind it | [authentication.md](authentication.md) |
| `Requester.swift` | What asked and where it was started, text safe to display, the prompt wording | [authentication.md](authentication.md#the-requesting-process) |
| `ProcessAncestry.swift` | Reads a process, its arguments and its ancestors from the kernel | [authentication.md](authentication.md#how-the-processes-are-read) |
| `AuthCache.swift` | The remembered authentication | [reuse-window.md](reuse-window.md) |
| `SessionScope.swift` | Which terminal session a process belongs to | [reuse-window.md](reuse-window.md#session-scope) |
| `Settings.swift` | Loads and checks the settings file | [settings.md](settings.md) |
| `Makefile` | Build, sign, install, verify, uninstall | [installation.md](installation.md) |
