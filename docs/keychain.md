# Keychain storage

How secrets are stored and why only `keychain-touchid` can read them.
Code: `Sources/keychain_touchid/KeychainStore.swift`.

## What an item is

A secret is an ordinary **generic password** item in the user's default keychain,
which is the login keychain unless the user changed it. There is no separate
keychain file.

| Attribute | Value |
| --- | --- |
| Service | The first name given on the command line |
| Account | The second name |
| Description (shown as *Kind* in Keychain Access) | A marker: `keychain-touchid secret` |
| Password | The secret, as raw bytes |

Service and account together identify an item. The marker tells the tool's own
items apart from everything else in the keychain: every query the tool makes
includes it.

Records of a remembered authentication are stored the same way with the marker
`keychain-touchid cache`; see [reuse-window.md](reuse-window.md).

## The trust list

The Keychain keeps, for every item, a list of programs that may read its
password without asking the user. An item added without an explicit access
object trusts exactly one program: the one that added it. Programs are
identified by code signature; for an ad-hoc signed binary that is the hash of
its code (`cdhash`).

These facts were checked with test binaries on a throwaway keychain, and the
design rests on each of them:

| Fact | Consequence |
| --- | --- |
| The program that created an item reads it silently | `get` needs no Mac password |
| Any other program is refused and macOS asks for the Mac password | Other programs stay locked out |
| The same binary at another path still reads silently | The binary can be built in one place and installed in another |
| Signing a binary again changes its identity | The binary is signed before the first `set`; every rebuild is a new program to the Keychain |
| Updating an item's value keeps its trust list | `set` can replace a value in place; but see [foreign items](#own-foreign-absent) |
| A program that is not trusted can still overwrite or delete an item | Only reading is protected; `set` and `delete` do not authenticate |
| Looking up an item's attributes needs no trust | Checking existence and `list` never prompt |

## Own, foreign, absent

Before acting on an item the tool determines its state with two attribute-only
lookups: one with the marker, one without.

| State | Meaning | `get` | `set` | `delete` |
| --- | --- | --- | --- | --- |
| own | The item carries the marker | Authenticate, read | Replace the value in place | Remove |
| foreign | Same service and account, no marker | Not found | Refuse, with a hint | Not found |
| absent | No such item | Not found | Add | Not found |

A foreign item is never adopted. Updating it would keep its trust list, so the
programs that could read it silently before could still read the new secret.
The README describes how to move such a secret instead.

## Operations

| Operation | Keychain call | Notes |
| --- | --- | --- |
| add | `SecItemAdd` | No access object, so the trust list is "only the creator" |
| update | `SecItemUpdate` | Changes the password only; the item and its trust list stay |
| read | `SecItemCopyMatching` returning data | The only operation the trust list guards |
| delete | `SecItemDelete` | |
| list | `SecItemCopyMatching` returning attributes | Sorted by service, then account |

Keychain status codes become `StoreError`:

| Status | `StoreError` |
| --- | --- |
| `errSecItemNotFound` | `notFound` |
| `errSecDuplicateItem` | `duplicateItem` |
| `errSecAuthFailed`, `errSecUserCanceled`, `errSecInteractionNotAllowed` | `accessDenied` |
| anything else | `unexpected(status)` |

## Reading without asking the user

A read by a program the item does not trust normally shows the Keychain password
dialog. A store created with `allowsUserInteraction: false` turns the Keychain's
user interaction off around the read, so such a read fails with `accessDenied`
instead. The switch is process-wide; the previous value is restored afterwards.

It is used for the records of remembered authentications, where an unreadable
record must count as "no record", and in the tests, which must never show a
dialog.

## Which keychain

`KeychainStore(keychain: nil)` works on the default keychain. The tests pass a
throwaway keychain file created for the test run, so they never touch the login
keychain.

## Why the file-based keychain

What macOS offers out of the box:

| Approach | Result |
| --- | --- |
| A Keychain item that trusts `/usr/bin/security` (the default when created with it) | Any process running as the user reads it silently |
| A Keychain item with an empty trust list (`-T ""`) | Every read asks for the **Mac password** |
| The data-protection keychain with biometric access control | Needs a signed app with entitlements, which requires a paid Apple Developer account |

The tool takes the middle ground: an item that trusts one binary, and that
binary asks for Touch ID.

The data-protection keychain could bind an item to biometric authentication
directly, but an ad-hoc signed binary cannot have the entitlements it requires.
The file-based keychain needs none. The price is two process-wide calls
(`SecKeychainGetUserInteractionAllowed`, `SecKeychainSetUserInteractionAllowed`)
that Apple marks as deprecated without offering a replacement; the build warns
about them.

## Looking at the items

- Keychain Access: keychain **login**, search for the kind
  `keychain-touchid secret`.
- `keychain-touchid list`.
- `security find-generic-password -s <service> -a <account>` prints the
  attributes without asking; adding `-w` asks for the Mac password.
