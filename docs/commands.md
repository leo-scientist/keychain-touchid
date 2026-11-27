# Commands

What happens, step by step, when the tool runs.
Code: `Main.swift`, `Arguments.swift`, `Commands.swift`, `SecretInput.swift`,
`ExitCode.swift` in `Sources/keychain_touchid/`.

## A run from start to end

1. If the first argument is `help`, `-h` or `--help`, the usage text goes to
   stdout and the run ends with code 0. If it is `version` or `--version`, the
   same happens with `keytap <version>`.
2. The arguments are parsed into a command. A mistake ends the run with code 2,
   the message and the usage text on stderr.
3. The settings file is loaded ([settings.md](settings.md)). A file that exists
   but is not acceptable ends the run with code 1, whatever the command.
4. The command runs.
5. Any error becomes one line on stderr, prefixed with `keytap:`, and
   an [exit code](#exit-codes). If stderr cannot be written, the exit code is
   still delivered.

## Arguments

```
keytap set    <service> [account]
keytap get    [--no-cache] <service> [account]
keytap delete <service> [account]
keytap list   [service]
keytap --version
keytap handover
keytap receive
```

- Arguments that start with `-` are options. `get` accepts `--no-cache`; no
  other command accepts any. An unknown option is an error.
- A lone `--` ends the options: everything after it is a name, even if it starts
  with a dash.
- `set`, `get` and `delete` take a service and an optional account; `list`
  takes none or one; `handover` and `receive` take nothing.
- An omitted account is the name of the user running the tool, read from the
  user database, not from `$USER`, which the caller can set to anything. It
  follows the same [rules](#names) as a given one. If the name cannot be read,
  the account has to be given.

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
2. Read the secret ([below](#entering-a-secret)). If that fails, nothing has
   been touched.
3. *Absent*: create the item. If one appears in the meantime, fail and leave it
   alone.
4. *Own*: create the item anew, never write into the existing one
   ([keychain.md](keychain.md#writing-a-secret)):
   1. If the keychain is locked, stop with code 1. A locked keychain lets an
      item be removed but not created, so going on would lose the old value.
   2. Remove whatever has the name and create the item with the new value,
      repeating this if an item is put in the way.
   3. If that fails and the old item is gone, say so on stderr. The old value
      is never read, because that would be a read without authentication, so
      it cannot be put back.
5. Report on stderr: `created …` or `updated …`.

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

## `handover`

Run by `make update`, not meant to be typed. It moves every secret to the build
that is about to replace this one, while this build is still the one the
Keychain trusts; [installation.md](installation.md#updating) explains why and
what makes it safe.

1. List the tool's own secrets. With none, stop.
2. Check the successor, `/usr/local/bin/keytap.new`: it must be a
   regular file owned by root and not writable by group or others, in a
   directory with the same properties. Otherwise stop with code 1.
3. Check that the keychain is unlocked. A locked keychain refuses a read just
   as it refuses an untrusted program, so without this check every secret
   would be skipped and the update would go on without them. Stop with code 1.
4. Ask for one authentication, which names the number of secrets and who asked.
   A refusal ends with code 3. Up to here nothing has been read.
5. For each secret:
   1. Skip it, and report it at the end, if its name is not one the tool
      stores, or if this build is not trusted to read it. The read is made
      without letting the Keychain ask the user.
   2. Remove the item. The successor can only create it once it is gone,
      because service and account identify an item.
   3. Run the successor's [`receive`](#receive), feeding it the names and the
      secret through a pipe.
   4. If that fails, remove whatever now has the item's name and ask the
      successor again, up to three times. Nothing but the successor's own item
      belongs there: anything else was put there after the removal.
6. If a secret could not be read for any other reason, or still could not be
   handed over, take **all** of them back — remove what the successor created
   and create the items again under this build — and stop with code 1, saying
   on stderr that the hand-over was undone. Secrets that could not be taken
   back are named in the error instead; each has to be stored again with `set`.
7. Report how many secrets were handed over.

The successor is started with an empty environment and the single argument
`receive`.

## `receive`

The other half of the hand-over, run by `handover` in the new build.

1. Read one record from stdin: service, account and secret, each as a 4-byte
   big-endian length followed by that many bytes. The names travel this way
   rather than as arguments because the system rewrites the characters of
   program arguments, and the Keychain compares names byte for byte.
2. Refuse a record that is malformed, has names the tool does not store
   ([Names](#names)), or an empty or oversized secret.
3. **Create** the item. If an item with that service and account exists, marked
   or not, fail with code 1 and leave it untouched.

It never updates an item, which is the point: the Keychain trusts an item's
creator, so a secret written into an item somebody else created could be read
by them. There is no authentication, as with `set`: storing a value needs none.

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
| 1 | Failure | Keychain error, foreign item on `set`, locked keychain on `set`, unreadable input, settings file not acceptable, hand-over not possible |
| 2 | Usage | Wrong command, option or name; empty or oversized secret |
| 3 | Authentication | Authentication denied, cancelled or unavailable; the Keychain refused access |
| 4 | Not found | No such item, or it is not one of the tool's own |

`Failure(error)` in `ExitCode.swift` is the single place where an error from any
part becomes a code and a message.
