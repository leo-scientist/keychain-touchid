# Authentication

How the tool asks the user to confirm a read.
Code: `Authenticator.swift`, `Requester.swift` and `ProcessAncestry.swift` in
`Sources/keychain_touchid/`.

## When it happens

Before every read of a secret by `get`, and nowhere else. The only way to skip it
is a remembered authentication ([reuse-window.md](reuse-window.md)), which is off
unless the root-owned settings file turns it on. No command-line option and no
environment variable can skip it.

The check is not connected to the Keychain cryptographically. The Keychain lets
this binary read the item; the binary chooses to authenticate first. What makes
that reliable is described in [security.md](security.md).

## The prompt

The tool asks macOS for local authentication through the LocalAuthentication
framework (`LAContext.evaluatePolicy`). Each `get` uses a new context, so the
system never reuses an earlier success on its own.

| `policy` setting | LocalAuthentication policy | What the user can use |
| --- | --- | --- |
| `any` (default) | `deviceOwnerAuthentication` | Touch ID, Apple Watch, or the Mac password |
| `biometry` | `deviceOwnerAuthenticationWithBiometrics` | Touch ID only |

With `any`, the fallback covers a closed lid and locked-out biometry.

The dialog's second button reads **Deny** rather than Cancel: the user is
refusing a request made by another program, not cancelling an action of their
own.

Any outcome other than success — denied, failed, unavailable — ends the run with
exit code 3 and the system's description of the reason. The Keychain is not
read.

## Wording

The system starts the sentence with the program's name and ends it with a full
stop; the tool supplies the middle:

```
keychain-touchid is trying to give the secret “op-service-account” (sam)
to vault-pass.sh, running in Terminal.
```

| Part | Meaning |
| --- | --- |
| `“op-service-account” (sam)` | The secret: service, then account |
| `vault-pass.sh` | [What asked](#the-requesting-process) |
| `running in Terminal` | [Where it was started](#the-requesting-process) |

The sentence says "give … to" because that is what approving does: the secret
is handed to that program.

When the [reuse window](reuse-window.md) will apply, the sentence continues, so
that the user knows one approval covers more than one read:

```
…, and to let this terminal read it again for 5 minutes without asking.
```

The duration is given in the largest unit that is exact: `90 seconds`,
`5 minutes`, `24 hours`.

## The requesting process

The prompt has to let the user recognise an unexpected request, and "bash" does
not do that. So the tool looks at the process that ran it and at that process's
ancestors, as the kernel reports them.

**What asked** is the parent of the `keychain-touchid` process:

- If the parent is an interpreter running a script, the name is the script's
  file name: `vault-pass.sh`, `sync.py`. This holds when the parent is a known
  shell or scripting runtime and its first argument does not start with a dash.
  After an option such as `-c` the next argument may be a whole command line,
  so it is never taken for a script.
- Otherwise the name is the parent's executable name: `zsh`, `restic`.
- If the parent has already exited, `launchd`.

**Where it was started** comes from the ancestors:

| Situation | Shown | Example |
| --- | --- | --- |
| An application is among the ancestors | `running in` the outermost one | `running in Terminal` |
| The parent is itself that application | Nothing more | |
| No application, but further ancestors | `started by` the outermost one | `started by tmux` |
| The parent was started by launchd directly | `started by launchd` | A launch agent |

The outermost application is used because it is the one the user sees. Nearer
ones are helper processes of the same application, or an interpreter that
happens to be packaged as an application.

All names are made safe to display and cut to 64 Unicode scalars.

These are hints, not proof. A process chooses its executable's name and its
arguments, and can arrange its ancestry. The names help to notice a request that
does not match what the user is doing; they cannot authenticate the requester.

### How the processes are read

| What | Source |
| --- | --- |
| Parent of a process, its short name | `sysctl(KERN_PROC_PID)`; unlike `proc_pidinfo`, it also describes another user's process, such as root's `login` between a shell and its terminal |
| Executable path | `proc_pidpath` |
| Arguments | `sysctl(KERN_PROCARGS2)`, for the parent only; the kernel does not disclose another user's arguments |

## Text safe to display

Service, account and process name all end up in a dialog the user trusts, and
`list` prints names to a terminal. Characters in these Unicode categories are
considered unsafe: control, format (which includes text-direction overrides and
zero-width characters), line separator and paragraph separator.

- In a service or account given on the command line they are an error
  ([commands.md](commands.md#names)).
- In a process name, and in names printed by `list`, each is replaced with `?`,
  and text longer than the limit is cut and marked with `…`.

Lengths are counted in Unicode scalars, not visible characters, because one
visible character can carry any number of combining marks.
