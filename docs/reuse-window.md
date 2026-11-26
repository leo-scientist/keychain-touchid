# Reuse window

How a successful authentication can be remembered for a while.
Code: `AuthCache.swift` and `SessionScope.swift` in `Sources/keychain_touchid/`.

## In short

By default every `get` asks. With `cache_seconds` above zero in the
[settings file](settings.md), a successful authentication is remembered, and
further reads of **the same secret** from **the same terminal session** within
that many seconds do not ask again.

The cost is stated plainly: within the window, any process that belongs to that
terminal session gets the secret without a prompt.

## Session scope

A remembered authentication is tied to the terminal session it was given in, as
`sudo` does. The scope is three values, all taken from the kernel and none from
anything the caller controls:

| Value | Source | Purpose |
| --- | --- | --- |
| Session id | `getsid(0)` | Identifies the session, normally one terminal tab |
| Start time of the session leader | `sysctl` for that process | Tells the session apart from a later one that got the same id |
| Controlling terminal | `sysctl` for the tool's own process | A process without one has no scope at all |

`sysctl(KERN_PROC_PID)` is used rather than `proc_pidinfo`, because the leader of
a terminal session is usually the `login` process owned by root, and
`proc_pidinfo` refuses to describe another user's process.

What is inside and outside a session:

| Inside: no prompt within the window | Outside: always prompts |
| --- | --- |
| Commands typed in the tab | Other terminal tabs and windows |
| Scripts and programs started from it | GUI programs |
| Jobs sent to the background from it | Jobs started by launchd or cron |
| | Any process without a controlling terminal |

A process cannot join an existing session; it can only start a new one. That is
what makes the session a usable boundary.

## The record

A remembered authentication is a Keychain item of its own
([keychain.md](keychain.md)):

| Attribute | Value |
| --- | --- |
| Marker | `keychain-touchid cache` |
| Service | `keychain-touchid-cache:` followed by the secret's service |
| Account | The secret's account |
| Password | A small JSON document: creation time, session scope, SHA-256 of the secret |

There is one record per secret; a new authentication replaces it. Because the
prefix is reserved, a secret's own service may not start with it.

## When a record is valid

All of the following must hold; otherwise the tool authenticates as usual.

1. The reuse window is on, the caller has a session scope, and `--no-cache` was
   not given.
2. The record can be read without the Keychain asking the user. A record left by
   another build of the tool cannot, and counts as no record.
3. The record decodes.
4. Its session scope equals the caller's.
5. Its creation time lies between `now − cache_seconds` and `now`. A time in the
   future is rejected. The time is compared, never used in arithmetic, since it
   is whatever was written to the item.
6. Its hash equals the SHA-256 of the secret as it is now. The comparison takes
   the same time whatever the difference, because a record's hash is as good as
   an authentication to whoever could guess it.

Point 6 means the tool reads the secret before it knows whether the record is
valid. The secret stays in the tool's memory and is printed only if the check
passes.

## Lifecycle

- **Written** after a successful authentication, as delete followed by add. An
  update would keep the trust list of the build that created the record, and a
  later build could not read it.
- **Not refreshed by a reuse.** The window counts from the authentication, not
  from the last read, so it cannot be kept open by reading repeatedly.
- **Invalidated** by time, by any change of the secret, and by `delete`, which
  removes the record.
- **`--no-cache`** skips the lookup. After the authentication the record is
  written as usual.
- **Failures are soft.** Anything wrong while reading a record means
  "authenticate". Failing to write or remove one is a warning on stderr; the
  exit code is unaffected.

## Why it is built this way

Any process running as the user can overwrite or delete a Keychain item without
a password ([keychain.md](keychain.md#the-trust-list)). That rules out the
simpler designs:

| Design | Why not |
| --- | --- |
| A file with a timestamp | Any process can write one |
| A timestamp in a Keychain item | Any process can overwrite the item with a fresh timestamp |
| A record signed with a key kept in another Keychain item | Any process can replace the key with one it knows, then sign its own record |
| A window chosen by an option or an environment variable | The caller, including a hostile one, would choose it |

The record used here cannot be forged, because a valid one contains the hash of
the secret, and whoever does not already know the secret cannot produce it. An
attacker who replaces both the secret and the record gets only its own secret
back. Reading the hash requires the same trust as reading the secret.

The record's session and time are not secret, but changing them means writing a
new record, which again needs the hash.
