# Security

What the tool protects, what each protection relies on, and what it does not do.

## What is protected, and from whom

The protected thing is the **value of a secret**. The adversary is another
process running as the same user: a script, a tool, a compromised dependency —
something that can run programs and read the user's files, but is not root and
does not already control the user's whole session.

Without the tool, such a process reads an environment variable or a dotfile
silently. With it, reading a secret takes an authentication the user sees.

## The chain

The Touch ID check is made by the `keytap` binary, not by the
Keychain. So the protection is a chain, and each link has its own defence:

| Link | What could go wrong | Defence |
| --- | --- | --- |
| Only this binary reads the item | Another program reads it through the Keychain | The item's trust list holds only this binary ([keychain.md](keychain.md)); others get the Mac password prompt |
| The binary authenticates first | The binary is made to skip the check | No option, environment variable or user-writable file can skip it; [settings](settings.md) come only from a root-owned file |
| The binary runs unmodified | Code is injected, or a debugger reads the secret from memory | Signed with the hardened runtime (`codesign --options runtime`): `DYLD_INSERT_LIBRARIES` is ignored and attaching a debugger is refused |
| The binary on disk is the real one | The file is replaced | Installed in `/usr/local/bin`, owned by root. A replaced binary also has a different signature, so the Keychain would not trust it |
| The user approves a known request | A prompt is disguised or unexpected | The dialog names the item, what asked for it and where that was started, and says when the approval will be reused; names cannot contain characters that disguise text ([authentication.md](authentication.md)) |

Further measures:

| Risk | Defence |
| --- | --- |
| An update hands every secret to another program | `handover` gives them only to the build at one fixed path that root installed, after an authentication that says so ([installation.md](installation.md#why-this-is-safe)) |
| A secret stored earlier by another program stays readable by it | Foreign items are never touched ([keychain.md](keychain.md#own-foreign-absent)) |
| Another process puts an item of its own under a secret's name, so that the next value is written into it | A secret is only ever written by creating the item, which only its creator can read; an item in the way is removed ([keychain.md](keychain.md#writing-a-secret)) |
| The place where secrets are created is pointed at a keychain another process controls | Every operation names the login keychain by its path; the default keychain, the search list and `$HOME` play no part ([keychain.md](keychain.md#which-keychain)) |
| A program named `keytap` earlier in `PATH` stands in | Use the full path in scripts; such a program cannot read the item silently anyway |
| A remembered authentication is forged or used from elsewhere | The record holds the hash of the secret and is tied to the terminal session ([reuse-window.md](reuse-window.md)) |

## What it does not do

- **It does not guard other programs' items.** It manages only the secrets
  stored with it. A program that reads the Keychain directly never goes through
  it.
- **It does not protect against deletion or replacement.** Any process running
  as the user can remove a Keychain item, or change its value, without a
  password. A changed item can then be read by nobody without the Mac password,
  the tool included ([keychain.md](keychain.md#what-another-program-can-do)).
  Only reading is protected.
- **It cannot vouch for the requester.** The names in the dialog come from the
  requesting process and its ancestors, which choose their own names and
  arguments.
- **It does not work unattended.** The prompt is shown on the Mac's screen.
- **With the reuse window on**, any process in the same terminal session gets
  the secret without a prompt until the window ends.
- **It is not a sandbox.** Malware that already controls the user's session —
  that can, for example, edit `~/.zshrc` or drive the terminal — is out of
  scope. So is anything running as root.
- **Secrets are not wiped from memory.** The hardened runtime is what keeps
  other processes from reading the tool's memory.

## Keychain prompts

A Keychain prompt asking for the Mac password about one of these items means a
program other than the build that stored it is trying to read it. `make update`
avoids that by handing the secrets over to the new build; the only expected case
is a secret that [could not be handed over](installation.md#when-secrets-could-not-be-handed-over).

Never answer **Always Allow** for any other program, including a development
build (`swift build`, `swift run`): it has no hardened runtime, and it would be
added to the item's trust list permanently.

## Rules for changing the code

- Nothing may let a caller weaken or skip authentication: no option, no
  environment variable, no file the user can write.
- A secret is written only by creating an item. Nothing may change the value of
  an existing item.
- Every Keychain call names the keychain it works on. Nothing may fall back to
  the default keychain or the search list.
- An option may only tighten behaviour.
- Only `get` and `handover` read a secret's value, each only after an
  authentication, as described in [commands.md](commands.md).
- `handover` gives secrets to nothing but the root-owned successor at its fixed
  path, and `receive` only ever creates an item.
- Text that reaches the dialog or the terminal from outside — arguments, process
  names, names read back from the Keychain — is validated or sanitized.
- Data read back from the Keychain is treated as written by anyone.
- A settings problem is an error, never a fallback.
