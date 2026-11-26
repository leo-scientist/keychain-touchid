# keychain-touchid

A small macOS CLI that keeps secrets in the login Keychain and hands one out
only after Touch ID — on **every** read by default.

```sh
$ keychain-touchid get github-token "$USER"
# Touch ID prompt, then the value on stdout
```

## What it is for

Tokens and passwords that tools and scripts need usually sit in an environment
variable or a dotfile, where any process running as you can read them silently.

With `keychain-touchid` a secret stays in the macOS Keychain, and reading it
takes a touch:

- **You confirm each read.** The prompt names the secret and the program that
  asked for it.
- **Other programs stay locked out.** They still need your Mac password to read
  the secret.
- **Nothing new to trust with your data.** It is the standard login Keychain;
  there is no separate vault, file or service.
- **Works from anything that can run a command**: shell functions, scripts,
  tools with a "password command" setting.

## Quick start

You need macOS 13 or later, a Swift 6.4 toolchain (Xcode or the Command Line
Tools) and `sudo`.

```sh
make install                                          # build, sign, install into /usr/local/bin
pbpaste | keychain-touchid set github-token "$USER"   # store a secret from the clipboard
keychain-touchid get github-token "$USER"             # Touch ID, then the value
```

A secret is addressed by two names of your choice: a **service** (what it is
for) and an **account** (whose it is).

## Commands

| Command | What it does |
| --- | --- |
| `keychain-touchid set <service> <account>` | Stores a secret, or replaces an existing one. The value comes from a pipe, or from a hidden prompt |
| `keychain-touchid get <service> <account>` | Asks for Touch ID, then prints the secret |
| `keychain-touchid delete <service> <account>` | Removes the secret |
| `keychain-touchid list [service]` | Lists the names of stored secrets, never their values |

Only `get` asks for Touch ID. The exit code tells a script what happened: `0`
success, `3` authentication refused, `4` no such secret.

More: [commands in detail](docs/commands.md) — input limits, name rules, all
exit codes.

## Using it in scripts and tools

Run `get` where the secret is needed and use its output. Use the full path, so
nothing else on your `PATH` can stand in for it:

```sh
token="$(/usr/local/bin/keychain-touchid get github-token "$USER")" || exit 1
```

A tool that accepts a password command can call it directly:

```sh
export RESTIC_PASSWORD_COMMAND='/usr/local/bin/keychain-touchid get restic my-repo'
```

More: [recipes](docs/recipes.md) — a secret for one program only, the
1Password CLI, Ansible, moving a secret you already have in the Keychain.

## How it works

1. `keychain-touchid` creates the Keychain item itself, so the Keychain lets
   only this program read it without the Mac password.
2. Before each read the program asks for Touch ID, with the Mac password or
   Apple Watch as a fallback.
3. Only then does it read the secret and print it.

In Keychain Access your secrets are under **login**, with the kind
`keychain-touchid secret`.

More: [Keychain storage](docs/keychain.md),
[authentication](docs/authentication.md).

## Settings

None are needed. Two can be changed in a root-owned file,
`/usr/local/etc/keychain-touchid.conf`:

| Setting | Default | What it changes |
| --- | --- | --- |
| `cache_seconds` | `0` | Reuse one authentication for this many seconds, within the same terminal tab |
| `policy` | `any` | `biometry` accepts Touch ID only, without the password fallback |

More: [settings](docs/settings.md), [the reuse window](docs/reuse-window.md).

## Install, update, uninstall

```sh
make install     # build, sign, install as root, verify
make update      # the same, after changing the sources
make verify      # check the installation
make uninstall   # remove the program; your secrets stay in the Keychain
```

After an update the Keychain sees a new program, so the first read of each
secret asks for your Mac password once.

More: [installation](docs/installation.md).

## What it does not do

- It protects only the secrets you store with it, not other programs' Keychain
  items.
- It protects a secret from being read, not from being deleted or replaced.
- It needs you at the Mac: the prompt appears on its screen.
- It raises the bar; it is not a sandbox against malware that already controls
  your account.

More: [security](docs/security.md).

## Documentation

Everything else is in [docs/](docs/INDEX.md).
