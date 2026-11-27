# Recipes

Ways to use a stored secret from other programs.

## The pattern

Run `keytap get` where the secret is needed and use its output.

- Call the binary by its full path, `/usr/local/bin/keytap`, so a
  directory earlier in `PATH` cannot stand in for it.
- Check the exit code: a refused authentication prints nothing and returns 3
  ([commands.md](commands.md#exit-codes)).
- The caller does not need a terminal. Anything in your login session that can
  run a program gets the same prompt.

## A tool with a "password command" setting

Many tools can run a command to obtain a password. For example restic:

```sh
export RESTIC_PASSWORD_COMMAND='/usr/local/bin/keytap get restic my-repo'
```

## A secret for one program only

A shell function that puts the secret into the environment of a single process
and nowhere else. Here the 1Password CLI, in `~/.zshrc`:

```sh
op() {
  local token
  token="$(/usr/local/bin/keytap get op-service-account)" || return 1
  OP_SERVICE_ACCOUNT_TOKEN="$token" command op "$@"
}
```

## A script another tool runs

Here an Ansible `vault-pass.sh`, which fetches the vault password from
1Password using the token above:

```sh
#!/bin/sh
token="$(/usr/local/bin/keytap get op-service-account)" || exit 1

OP_SERVICE_ACCOUNT_TOKEN="$token" exec op read "op://<vault>/<item>/<field>"
```

## Several reads in a row

A script that needs the secret many times can read it once into a variable. If
separate commands in one terminal each need it, consider the
[reuse window](reuse-window.md).

## Moving an existing secret

A secret that already sits in the Keychain has to be stored again by
`keytap`. It cannot take over the old item, because that item would
keep trusting the programs that could read it before
([keychain.md](keychain.md#own-foreign-absent)). The old item is removed only if
the new one was stored:

```sh
security find-generic-password -s <old-service> -a <account> -w \
  | /usr/local/bin/keytap set <new-service> <account> \
  && security delete-generic-password -s <old-service> -a <account>
```

- The new item needs a different service or account name while the old one
  exists.
- macOS may ask for the Mac password to read the old item.
- The one-liner is for single-line ASCII secrets: `security` prints anything
  else as hex, and that hex text is what would be stored.
- Do this only for secrets that are yours. An application that relies on the old
  item will no longer find it.
