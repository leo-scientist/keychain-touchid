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

The Touch ID check is made by the `keychain-touchid` binary, not by the
Keychain. So the protection is a chain, and each link has its own defence:

| Link | What could go wrong | Defence |
| --- | --- | --- |
| Only this binary reads the item | Another program reads it through the Keychain | The item's trust list holds only this binary ([keychain.md](keychain.md)); others get the Mac password prompt |
| The binary authenticates first | The binary is made to skip the check | No option, environment variable or user-writable file can skip it; [settings](settings.md) come only from a root-owned file |
| The binary runs unmodified | Code is injected, or a debugger reads the secret from memory | Signed with the hardened runtime (`codesign --options runtime`): `DYLD_INSERT_LIBRARIES` is ignored and attaching a debugger is refused |
| The binary on disk is the real one | The file is replaced | Installed in `/usr/local/bin`, owned by root. A replaced binary also has a different signature, so the Keychain would not trust it |
| The user approves a known request | A prompt is disguised or unexpected | The dialog names the item and the requesting process; names cannot contain characters that disguise text ([authentication.md](authentication.md)) |

Further measures:

| Risk | Defence |
| --- | --- |
| A secret stored earlier by another program stays readable by it | Foreign items are never adopted ([keychain.md](keychain.md#own-foreign-absent)) |
| A program named `keychain-touchid` earlier in `PATH` stands in | Use the full path in scripts; such a program cannot read the item silently anyway |
| A remembered authentication is forged or used from elsewhere | The record holds the hash of the secret and is tied to the terminal session ([reuse-window.md](reuse-window.md)) |

## What it does not do

- **It does not guard other programs' items.** It manages only the secrets
  stored with it. A program that reads the Keychain directly never goes through
  it.
- **It does not protect against deletion or replacement.** Any process running
  as the user can delete a Keychain item or overwrite its value without a
  password. Only reading is protected.
- **It cannot vouch for the requester.** The process name in the dialog is the
  name of the parent's executable, which that process chooses.
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
program other than the installed binary is trying to read it. The only expected
case is the first read after `make install` or `make update` of a changed build
([installation.md](installation.md#after-a-rebuild)).

Never answer **Always Allow** for any other program, including a development
build (`swift build`, `swift run`): it has no hardened runtime, and it would be
added to the item's trust list permanently.

## Rules for changing the code

- Nothing may let a caller weaken or skip authentication: no option, no
  environment variable, no file the user can write.
- An option may only tighten behaviour.
- Only `get` reads a secret's value, and only after the checks in
  [commands.md](commands.md#get).
- Text that reaches the dialog or the terminal from outside — arguments, process
  names, names read back from the Keychain — is validated or sanitized.
- Data read back from the Keychain is treated as written by anyone.
- A settings problem is an error, never a fallback.
