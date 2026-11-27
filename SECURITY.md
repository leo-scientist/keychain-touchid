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

## What happens to a report

1. **Acknowledgement** within 14 days, in the advisory.
2. **Assessment.** The maintainer reproduces the problem and says whether it is a vulnerability and how severe it
   is. If it is not one, the advisory says why and is closed.
3. **Fix**, prepared in the advisory's private fork, with a test that fails without it. You are invited to check
   it.
4. **Release** with the fix, then **disclosure**: the advisory is published, with a CVE requested from GitHub, and
   the release notes point to it.
5. **Credit**: the advisory and the release notes name you as the reporter, unless you prefer otherwise.

The report stays private until step 4. If a fix takes longer than 90 days, the maintainer tells you why and agrees
a date with you.

## Scope

[docs/security.md](docs/security.md) lists what the tool protects against and what it does not. A report about
something listed there as not protected, such as malware that already controls your account, is welcome when it
shows a way around a protection that document claims.
