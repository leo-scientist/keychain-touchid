# Security policy

## Supported versions

Only the latest release gets fixes. Update by building it and running `make update`
([docs/installation.md](docs/installation.md#updating)).

## Reporting a vulnerability

Report it privately, not in a public issue, through
[GitHub's private vulnerability reporting](https://github.com/leo-scientist/keychain-touchid/security/advisories/new)
(the **Security** tab, **Report a vulnerability**).

Include:

- the version (`keytap --version`) and the macOS version;
- the steps that show the problem;
- what someone gains by it: a secret read without Touch ID, a disguised prompt, a weakened setting.

The report stays private while it is fixed. The vulnerability is disclosed in a GitHub security advisory once a
release with the fix is out, crediting you unless you prefer otherwise.

## Scope

[docs/security.md](docs/security.md) lists what the tool protects against and what it does not. A report about
something listed there as not protected, such as malware that already controls your account, is welcome when it
shows a way around a protection that document claims.
