# Installation

Installing, updating and removing the tool. Code: `Makefile`, and
`Sources/keychain_touchid/Handover.swift` for the update.

## Requirements

- macOS 13 or later.
- A Swift 6.2 or later toolchain: Xcode or the Command Line Tools.
- `sudo`, because the binary and the settings file are owned by root.

The tool is installed only by building it from source. A package manager such
as Homebrew would put it under a prefix that you can write to
(`/opt/homebrew` on Apple Silicon), so any process running as you could replace
the binary that holds the Keychain's trust. That defeats what the tool is for
([security.md](security.md)).

## Checking the sources

Release tags after `0.1.0` are signed with the maintainer's GPG key, whose
fingerprint is:

```
FFB5 291C F893 FBA2 803E  6684 5B34 EBF0 8039 2366
```

To check a release before building it, import the key from GitHub, make sure
its fingerprint is the one above, and verify the tag:

```sh
curl -fsSL https://github.com/leo-scientist.gpg | gpg --import
gpg --fingerprint 5B34EBF080392366
git verify-tag 0.2.0
git switch --detach 0.2.0
```

`git verify-tag` must say `Good signature`. GPG may add that the key is not
certified with a trusted signature; that only means you have not signed the key
yourself. A missing or bad signature means the sources are not the ones
released: do not build them.

## Commands

| Command | What it does |
| --- | --- |
| `make install` | Builds, signs, installs, then runs `make verify` |
| `make install DESTDIR=<dir>` | Builds, signs, and copies the files under `<dir>` for a package ([staging](#staging-for-a-package)) |
| `make update` | The same; use it after changing the sources. It never fetches sources itself |
| `make verify` | Checks an installation |
| `make uninstall` | Removes the binary, the settings file and the zsh completion |
| `make purge` | Deletes every secret the tool stored, after you confirm |
| `make build` | Builds the release binary only |
| `make test` | Runs the tests |
| `make clean` | Removes build products |

## What `make install` does

1. Builds the release binary (`swift build -c release`).
2. Signs it ad hoc with the hardened runtime
   (`codesign --sign - --force --options runtime`).
3. Creates `/usr/local/bin`, `/usr/local/etc` and
   `/usr/local/share/zsh/site-functions` if they do not exist.
4. Installs the binary as `/usr/local/bin/keytap`, owner
   `root:wheel`, mode `755`. If a different build is already installed, the
   secrets are first [handed over](#updating) to the new one.
5. If there is no settings file, installs the commented sample as
   `/usr/local/etc/keytap.conf`, owner `root:wheel`, mode `644`. An
   existing file is left alone.
6. Installs the [zsh completion](#shell-completion) as
   `/usr/local/share/zsh/site-functions/_keytap`, owner `root:wheel`, mode
   `644`, unless the same file is already there.
7. Runs `make verify`.

The paths are fixed. The location must be owned by root, and the settings path
is built into the binary.

## Staging for a package

For building a package, `make install DESTDIR=<dir>` (or `DESTDIR` set in the
environment) builds and signs as usual, then only copies the files under
`<dir>`:

| File | Mode |
| --- | --- |
| `<dir>/usr/local/bin/keytap` | `755` |
| `<dir>/usr/local/etc/keytap.conf.sample` | `644` |
| `<dir>/usr/local/share/zsh/site-functions/_keytap` | `644` |

It uses no `sudo`, sets no owner, hands no secrets over and runs no
`make verify`. The sample is staged under its own name, so a package never
overwrites someone's settings file.

The paths under `<dir>` cannot be moved to another prefix: the binary has them
built in. The package must install the files at exactly these paths, owned by
`root:wheel`; anything else gives up the protection the tool exists for
([requirements](#requirements)). A package that replaces an installed build
does not hand the secrets over either: each of them then asks for the Mac
password until it is [stored again](#when-secrets-could-not-be-handed-over).

## Shell completion

In zsh, Tab completes the commands, then the service and account names of
stored secrets, taken from `keytap list`. That never reads a value and never
asks for Touch ID. The file comes from `completions/_keytap`; the directory it
is installed in is on zsh's default `fpath`. If completion does not start in a
new terminal, your `~/.zshrc` must call `compinit`.

## Updating

```sh
make update
```

**What you are asked for:** your password for `sudo`, once, and one Touch ID
confirmation to move the secrets. After that every secret works as before, with
Touch ID only. No Keychain password prompts.

### Why an update needs a step of its own

The Keychain identifies the program allowed to read a secret by its signature,
and an ad-hoc signature changes with every change of the code
([keychain.md](keychain.md#the-trust-list)). To the Keychain a new build is a
different program: it could read none of the secrets the installed build
stored, and macOS would ask for the Mac password on every read of every secret.

### What happens

While the installed build is still the one the Keychain trusts, it hands its
secrets over to the new build:

1. The new build is installed next to the old one as
   `/usr/local/bin/keytap.new`, owned by root.
2. The installed build runs `keytap handover`
   ([commands.md](commands.md#handover)). It asks for one authentication that
   names the number of secrets, then for each secret: reads it, removes the
   item, and has the new build create it again. The new item trusts the new
   build, and only that one.
3. The new build replaces the old one.

Either every secret moves, or the update stops and every secret is back with
the installed build.

### Why this is safe

- **Secrets go only to a build that root installed.** `handover` gives them to
  the program at the one fixed path, and only if that file is owned by root and
  neither it nor its directory can be changed by anyone else. A process that
  merely runs as you cannot put a program there.
- **It still takes your confirmation.** The dialog says that all secrets are
  being handed to a new build, and who asked.
- **A secret is only ever written by creating an item.** Only an item's creator
  can read it silently. The new build never writes into an item that already
  exists, so a secret cannot land in an item another process put in the place
  of one that was just removed. Such an item makes the creation fail; it is
  then removed and the creation is tried again.
- **Names and values travel as exact bytes** from one process to the other
  through a pipe. Nothing is written to a file, put on a command line or
  printed.
- **Nothing is lost if the new build fails.** The installed build keeps each
  secret in memory until the whole hand-over has succeeded, and takes all of
  them back if it does not. Should taking one back fail as well, the tool names
  it ([If the update stops](#if-the-update-stops)).
- **The old build loses access.** After the hand-over an item trusts only the
  new build.

From the start of the hand-over until the new build is in place, `make update`
ignores Ctrl+C, a closed terminal and requests to end it, so the hand-over
cannot stop halfway; to stop the update, cancel the Touch ID dialog. After a
Ctrl+C there, `make` stops once the new build is in place, without checking
it: run `make verify`.

One narrow risk remains: nothing can ignore `kill -9` or a crash. If the
installed build ends that way while secrets move, those already moved can be
read only with the Mac password; store them again as shown
[below](#when-secrets-could-not-be-handed-over). A secret that was between its
removal and its creation by the new build is gone; store it again with `set`.

### If the update stops

`make update` then removes `keytap.new` and leaves the installed build
in place. What became of the secrets is said by `handover` itself, the only part
that knows.

| Situation | What to do |
| --- | --- |
| You denied the authentication | Nothing was changed. Run `make update` again |
| The keychain is locked | Unlock it (it unlocks when you log in) and run `make update` again |
| The new build could not store a secret | The tool says the hand-over was undone: every secret is back with the installed build. Fix the cause and run `make update` again |
| The message names secrets that "could not be taken back" | Each of those is either still stored for the new build, which is gone, or not stored at all any more. `get` tells which. If it prints the value after asking for the Mac password, store it again as shown [below](#when-secrets-could-not-be-handed-over); otherwise store it again with `set` from wherever you keep it |

### When secrets could not be handed over

The hand-over skips, and names, every secret the installed build is not trusted
to read. Such a secret still works, but macOS asks for the Mac password on every
read until it is stored again by the current build:

```sh
/usr/local/bin/keytap get <service> <account> \
  | /usr/local/bin/keytap set <service> <account>
```

This asks for Touch ID and the Mac password one last time; **Allow** is enough.
`set` creates the item anew, so it then trusts the current build. If the read is
refused, nothing is changed. One caveat: a secret that ends in a line break loses that
one line break.

Answering **Always Allow** at the Keychain prompt is the built-in alternative;
it keeps the old build on the item's trust list as well.

Installing the same build again changes nothing and needs no hand-over.

Never answer **Always Allow** for any other program
([security.md](security.md#keychain-prompts)).

## What `make verify` checks

- The binary exists, is owned by `root:wheel` and has mode `755`.
- `/usr/local/bin` is owned by root and not writable by others.
- The signature is valid and the hardened runtime is on.
- `keytap` found through `PATH` is the installed binary.
- No unfinished update is left behind.
- The zsh completion is installed.
- The settings file, if present, is owned by root, not writable by group or
  others, and accepted by the tool.

## Uninstalling

`make uninstall` prints the secrets that remain, then removes the binary, the
settings file and the zsh completion. Secrets stay in the Keychain, where they can be read with the Mac
password in Keychain Access. To remove one:

```sh
security delete-generic-password -s <service> -a <account>
```

## Deleting every secret

```sh
make purge
```

Lists the secrets the tool stored and asks you to type `delete`. Any other
answer, or none, removes nothing. Then each secret is deleted, together with its
remembered authentication.

- The question guards against a slip of the hand, nothing more: deleting a
  Keychain item needs no authentication, so there is no Touch ID prompt
  ([keychain.md](keychain.md#what-another-program-can-do)).
- It is separate from `make uninstall` on purpose: removing the program should
  not cost you the secrets.
- It works before or after `make uninstall`: it uses the installed build, or the
  built one when nothing is installed.
- An item that carries the tool's kind but a name the tool would not have stored
  was put there by something else. It is reported as not removed; delete it in
  Keychain Access.
- Items of other programs are never touched.
