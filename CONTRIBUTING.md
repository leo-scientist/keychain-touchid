# Contributing

Bug reports and pull requests are welcome. Report security problems as [SECURITY.md](SECURITY.md) describes, not
in an issue.

Before opening a pull request:

- Read [docs/development.md](docs/development.md): layout, conventions, how the code is tested.
- Keep to the [rules for changing the code](docs/security.md#rules-for-changing-the-code). A change that breaks
  one is not merged, whatever else it adds.
- Add automated tests with every new feature and bug fix: tests that fail without the change. A pull request
  without them is not merged, unless the change is one that tests cannot cover (see the last point).
- Run `make lint test smoke`; CI runs the same. `make format` fixes most lint findings.
- When behaviour changes, update the document that [docs/INDEX.md](docs/INDEX.md) lists for the file, and add a
  line under *Unreleased* in [CHANGELOG.md](CHANGELOG.md).
- For what tests cannot cover — the dialog, the hidden prompt, installation — say which rows of the
  [acceptance checklist](docs/development.md#acceptance-checklist) you ran.
