# Settings

The optional settings file. Code: `Sources/keychain_touchid/Settings.swift`.

## Location and defaults

`/usr/local/etc/keytap.conf`. The path is fixed in the binary.

Without the file, the defaults apply: ask on every read, accept Touch ID, Apple
Watch or the Mac password. `make install` puts a sample there with every setting
commented out, which is the same as no file.

## Settings

| Setting | Values | Default | Meaning |
| --- | --- | --- | --- |
| `cache_seconds` | whole number, `0`–`86400` | `0` | How long a successful authentication is reused; `0` asks every time. See [reuse-window.md](reuse-window.md) |
| `policy` | `any`, `biometry` | `any` | What counts as authentication. See [authentication.md](authentication.md#the-prompt) |

Example:

```
# reuse an authentication for five minutes, Touch ID only
cache_seconds = 300
policy = biometry
```

## Format

- One setting per line: `name = value`. Spaces around the name and the value are
  ignored.
- `#` starts a comment that runs to the end of the line.
- Empty lines are ignored. Any kind of line ending is accepted.
- Each setting may appear once.

## Who may write it

Both settings can weaken authentication, so they must be out of reach of a
process that merely runs as the user. The tool accepts the file only if it is:

- a regular file, not a symbolic link;
- owned by root;
- not writable by its group or by others;
- at most 64 KiB.

The file is opened once without following a symbolic link, and the checks and
the read all use that one open descriptor, so the file cannot be swapped between
the check and the read.

For the same reason nothing that weakens authentication can be given as a
command-line option or an environment variable. An option can only tighten:
`get --no-cache`.

To change a setting: `sudoedit /usr/local/etc/keytap.conf`.

## When something is wrong

An unknown setting, a value out of range, a repeated setting, a line that is not
`name = value`, or a file that fails the ownership checks ends **every** command
(except help) with exit code 1 and a message that names the line. The tool never
falls back to other values silently: the user would believe a stricter policy is
in force than the one actually used.

`make verify` checks the file's owner and permissions and that the tool accepts
it.
