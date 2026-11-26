# Authentication

How the tool asks the user to confirm a read.
Code: `Authenticator.swift` and `Requester.swift` in `Sources/keychain_touchid/`.

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

Any outcome other than success — cancelled, failed, unavailable — ends the run
with exit code 3 and the system's description of the reason. The Keychain is not
read.

## Wording

The dialog receives this reason:

```
read the secret “<service>” (<account>), requested by <process> (pid <N>)
```

It is written to complete the sentence the system starts with the program's
name. It names the item and the process that asked, so that a prompt nobody
expected can be recognised and denied.

## The requesting process

The requester is the parent of the `keychain-touchid` process: the shell
function, script or program that ran it.

- The name is the last component of the parent's executable path
  (`proc_pidpath`); if the path cannot be read, `unknown process`.
- The name is made safe to display and cut to 64 Unicode scalars.

It is a hint, not proof. A process chooses the name of its own executable, and
for a shell function the parent is simply the shell.

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
