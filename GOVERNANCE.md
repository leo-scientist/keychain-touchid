# Governance

keychain-touchid is a single-maintainer project: its author,
[@leo-scientist](https://github.com/leo-scientist), maintains it.

## Roles

| Role | Who | Responsibilities |
| --- | --- | --- |
| Maintainer | [@leo-scientist](https://github.com/leo-scientist) | Reviews and merges pull requests; triages issues; decides what goes into a release, and signs and publishes it; handles vulnerability reports as [SECURITY.md](SECURITY.md) describes; keeps CI, the workflows' actions and the documentation current; enforces the [code of conduct](CODE_OF_CONDUCT.md) |
| Contributor | Anyone who opens an issue or a pull request | Follows [CONTRIBUTING.md](CONTRIBUTING.md) and the code of conduct; signs off every commit |

## How decisions are made

Decisions are made in the open, in issues and pull requests. A larger change,
such as a new command or setting, starts as an issue, so its purpose can be
agreed before the work is done. The maintainer has the final say and gives the
reasons for it.

Two kinds of change are not accepted, whoever proposes them: one that breaks a
[rule for changing the code](docs/security.md#rules-for-changing-the-code), and
one outside the project's scope as set out in the [roadmap](ROADMAP.md).

## Continuity

The maintainer has named a successor in GitHub's account successor settings.
If the maintainer can no longer carry on, the successor can take over the
repository under GitHub's
[deceased user policy](https://docs.github.com/en/site-policy/other-site-policies/github-deceased-user-policy),
and with it issues, pull requests, releases and security advisories.

Until then, anyone can carry the project on from a fork. The license is MIT,
and the whole history, the documentation and the discussions are public.
Release tags are signed with the maintainer's key; a successor signs with their
own key and publishes it in [docs/installation.md](docs/installation.md#checking-the-sources).

The bus factor is one: the project depends on one person, and says so.
