# Commands

What happens, step by step, when the tool runs.
Code: `Main.swift`, `Arguments.swift`, `Commands.swift`, `SecretInput.swift`,
`ExitCode.swift` in `Sources/keychain_touchid/`.

## A run from start to end

1. If the first argument is `help`, `-h` or `--help`, the usage text goes to
   stdout and the run ends with code 0.
2. The arguments are parsed into a command. A mistake ends the run with code 2,
   the message and the usage text on stderr.
3. The settings file is loaded ([settings.md](settings.md)). A file that exists
   but is not acceptable ends the run with code 1, whatever the command.
4. The command runs.
5. Any error becomes one line on stderr, prefixed with `keychain-touchid:`, and
   an [exit code](#exit-codes). If stderr cannot be written, the exit code is
   still delivered.

## Arguments

```
keychain-touchid set    <service> <account>
keychain-touchid get    [--no-cache] <service> <account>
keychain-touchid delete <service> <account>
keychain-touchid list   [service]
```

- Arguments that start with `-` are options. `get` accepts `--no-cache`; no
  other command accepts any. An unknown option is an error.
- A lone `--` ends the options: everything after it is a name, even if it starts
  with a dash.
- `set`, `get` and `delete` take exactly two names; `list` takes none or one.

### Names

A service or account must:

| Rule | Why |
| --- | --- |
| Not be empty | An empty name would match nothing useful |
| Be at most 128 Unicode scalars | Names are shown in the authentication dialog. The length is counted in scalars, because a single visible character can carry any number of combining marks |
| Contain no control, formatting or line-separator characters | A line break, an escape sequence or a text-direction override could disguise the dialog |

A service must also not start with `keychain-touchid-cache:`, the prefix under
which remembered authentications are stored.

## `get`

1. Find out the item's state ([keychain.md](keychain.md#own-foreign-absent)).
   Anything but *own* ends with "not found" (code 4). This comes first so that a
   missing item never costs the user a prompt.
2. Unless `--no-cache` was given, look for a remembered authentication
   ([reuse-window.md](reuse-window.md)). If one is valid for this secret, print
   the secret, write `authentication reused from N s ago` to stderr, and stop.
3. Ask for authentication ([authentication.md](authentication.md)). A refusal
   ends with code 3; the Keychain has not been read.
4. Read the secret and print it.
5. If the reuse window is on, remember the authentication. A failure here is a
   warning on stderr and does not change the exit code.

## `set`

1. Find out the item's state. A *foreign* item ends with an error and a hint
   (code 1). This comes before asking for the secret, so a refusal does not
   waste the user's input.
2. Read the secret ([below](#entering-a-secret)).
3. *Own* item: replace its value in place, so a failed write never loses the old
   secret. *Absent*: add a new item.
4. Write `created …` or `updated …` to stderr.

There is no authentication: any process running as the user can overwrite a
Keychain item anyway, so a prompt would protect nothing.

## `delete`

1. Remove the item; if there is none of the tool's own, "not found" (code 4).
2. Remove the remembered authentication for it, if any. A failure here is a
   warning on stderr.

No authentication, for the same reason as `set`.

## `list`

Prints one line per stored secret, `service<TAB>account`, sorted by service and
then account; with an argument, only that service. Values are never read, so
there is no authentication.

Names are printed through the same sanitizing as text shown in the dialog
([authentication.md](authentication.md#text-safe-to-display)). Items come back
from the Keychain, where any process may have added one with the tool's marker
and a hostile name; one item must stay one line with one tab.

## Entering a secret

| Stdin | How the secret is read | Limit |
| --- | --- | --- |
| A pipe or a file | To the end of input. One trailing `\n` or `\r\n` is removed; nothing else is changed | 64 KiB |
| A terminal | A hidden prompt (`readpassphrase`), which turns echo off and restores the terminal itself, also when interrupted by Ctrl+C | 1022 bytes |

- An empty secret is refused.
- The terminal limit exists because a terminal line holds at most 1024 bytes
  (`MAX_CANON`); an entry that reaches the limit may already be truncated, so it
  is refused with a hint to use a pipe.
- Reading a pipe stops a few bytes past the limit, which is enough to know the
  limit was exceeded.
- A secret is handled as bytes throughout, never as text, so it need not be
  valid UTF-8.

## Output

- stdout carries only what a script consumes: the secret (`get`) or the listing
  (`list`).
- `get` prints the secret byte for byte and adds a newline only when stdout is a
  terminal.
- Everything meant for a person goes to stderr.

## Exit codes

| Code | Meaning | Errors |
| --- | --- | --- |
| 0 | Success | |
| 1 | Failure | Keychain error, foreign item on `set`, unreadable input, settings file not acceptable |
| 2 | Usage | Wrong command, option or name; empty or oversized secret |
| 3 | Authentication | Authentication denied, cancelled or unavailable; the Keychain refused access |
| 4 | Not found | No such item, or it is not one of the tool's own |

`Failure(error)` in `ExitCode.swift` is the single place where an error from any
part becomes a code and a message.
