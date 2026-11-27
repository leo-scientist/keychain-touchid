# Keychain storage

How secrets are stored and why only `keytap` can read them.
Code: `Sources/keychain_touchid/KeychainStore.swift`.

## What an item is

A secret is an ordinary **generic password** item in the user's login keychain.
There is no separate keychain file, and no other keychain is searched or
written ([Which keychain](#which-keychain)).

| Attribute | Value |
| --- | --- |
| Service | The first name given on the command line |
| Account | The second name |
| Description (shown as *Kind* in Keychain Access) | A marker: `keychain-touchid secret` |
| Password | The secret, as raw bytes |

Service and account together identify an item. The marker tells the tool's own
items apart from everything else in the keychain: every query the tool makes
includes it.

The markers carry the project's name, `keychain-touchid`, not the command's.
Changing them would hide every stored secret from the tool.

Records of a remembered authentication are stored the same way with the marker
`keychain-touchid cache`; see [reuse-window.md](reuse-window.md).

## The trust list

The Keychain lets a program read an item's password without asking the user
only if the program passes two checks kept with the item:

- it is on the item's list of **trusted applications**;
- its **partition** is on the item's partition list.

Both identify a program by its code signature; for an ad-hoc signed binary that
is the hash of its code (`cdhash`). An item added without an explicit access
object names exactly one program in both: the one that added it.

These facts were checked with test binaries on the **login keychain**, and the
design rests on each of them:

| Fact | Consequence |
| --- | --- |
| The program that created an item reads it silently | `get` needs no Mac password |
| Any other program is refused and macOS asks for the Mac password | Other programs stay locked out |
| The same binary at another path still reads silently | The binary can be built in one place and installed in another |
| Signing a binary again changes its identity | The binary is signed before the first `set`; every rebuild is a new program to the Keychain, so an update [hands the secrets over](installation.md#updating) |
| Looking up an item's attributes needs no trust | Checking existence and `list` never prompt |

### What another program can do

Also checked on the login keychain, with a second ad-hoc signed program:

| To an item it did not create, another program can | Result |
| --- | --- |
| Read the value | No. macOS asks the user for the Mac password |
| Change the value (`SecItemUpdate`) | Yes, silently. The trusted applications stay as they were and the partition becomes the changer's, so afterwards **no program passes both checks**: nobody reads the item without the Mac password, the tool included |
| Remove it with `SecItemDelete` | No: `errSecInvalidOwnerEdit` |
| Remove it through an item reference (`SecKeychainItemDelete`), or with `security delete-generic-password` | Yes, silently |
| Create an item under a free name, with any attributes, the tool's marker included | Yes |

What follows from it:

- Only reading is protected. `set` and `delete` do not authenticate, because a
  prompt there would protect nothing.
- The tool removes items through item references. `SecItemDelete` would fail on
  an item stored by an earlier build of the tool, which is another program to
  the Keychain.
- The tool never changes a value in place ([Writing a secret](#writing-a-secret)).

A keychain file created afresh, as the tests use, has no partition list. There a
changed item stays readable by its creator, and `SecItemDelete` works for
anyone. The tests therefore say nothing about behaviour between programs; the
tables above come from the login keychain.

## Own, foreign, absent

Before acting on an item the tool determines its state with two attribute-only
lookups: one with the marker, one without.

| State | Meaning | `get` | `set` | `delete` |
| --- | --- | --- | --- | --- |
| own | The item carries the marker | Authenticate, read | Create anew with the new value | Remove |
| foreign | Same service and account, no marker | Not found | Refuse, with a hint | Not found |
| absent | No such item | Not found | Add | Not found |

A foreign item is never touched: it may belong to another program.
[recipes.md](recipes.md#moving-an-existing-secret) describes how to move such a
secret.

## Writing a secret

A secret is only ever written by **creating** an item, never by changing the
value of an existing one.

Creating an item makes its creator the only program that passes both checks.
Changing the value of an item someone else created does not: on the login
keychain it leaves an item nobody can read without the Mac password
([above](#what-another-program-can-do)), and on a keychain without partition
lists it leaves the item's creator reading the new value. Neither is acceptable,
and the marker does not prove who created an item: any process can put it on an
item of its own.

So where an item is to be replaced — `set` on an existing secret, taking a secret
back during a failed update — the tool removes whatever has the name and creates
the item again. Between the removal and the creation another process can put an
item of its own there; then the creation fails, that item is removed, and the
creation is repeated, up to three times. The secret never lands in an item the
tool did not create.

A locked keychain lets an item be removed but not created. Replacing an item
there would lose the old value and store nothing, so it is refused before
anything is removed.

## Operations

| Operation | Keychain call | Notes |
| --- | --- | --- |
| add | `SecItemAdd` | No access object, so only the creator passes both checks |
| read | `SecItemCopyMatching` returning data | The operation the two checks guard |
| delete | `SecKeychainItemDelete` on the item's reference | Works for an item an earlier build stored; see [above](#what-another-program-can-do) |
| list | `SecItemCopyMatching` returning attributes | Sorted by service, then account |
| remove any | The same, without the marker | Only where the tool replaces an item it was entitled to: whatever has the name then is removed |
| replace | remove any, then add | The only way an existing secret gets a new value; refused while the keychain is locked; see [Writing a secret](#writing-a-secret) |

Keychain status codes become `StoreError`:

| Status | `StoreError` |
| --- | --- |
| `errSecItemNotFound` | `notFound` |
| `errSecDuplicateItem` | `duplicateItem` |
| `errSecAuthFailed`, `errSecUserCanceled`, `errSecInteractionNotAllowed` | `accessDenied` |
| anything else | `unexpected(status)` |

`locked` comes from no status: replace raises it when the keychain is locked.

## Reading without asking the user

A read by a program the item does not trust normally shows the Keychain password
dialog. A store created with `allowsUserInteraction: false` turns the Keychain's
user interaction off around the read, so such a read fails with `accessDenied`
instead. The switch is process-wide; the previous value is restored afterwards.

It is used for the records of remembered authentications, where an unreadable
record must count as "no record"; by the hand-over during an update, which
leaves alone a secret it is not trusted to read; and in the tests, which must
never show a dialog.

A locked keychain refuses such a read in exactly the same way, so code that
must tell the two apart asks the keychain for its lock state first.

## Which keychain

Every operation names one keychain: a search looks in that keychain only, and an
item is created in it. For the installed tool it is the login keychain, opened
by its path: `Library/Keychains/login.keychain-db` in the home directory the
user database gives.

It is deliberately not "the default keychain", and a search does not go through
the keychain search list:

- Both are settings of the user that a process running as the user can change,
  and the system finds them through `$HOME`. If they decided where a secret is
  created, such a process could point them at a keychain file it made itself and
  so controls. From then on every secret written would be its to read, and an
  update writes all of them.
- The search list also holds the System keychain. Its items are not the tool's
  to take for its own, and removing one is not the tool's business.

The tests give a store a throwaway keychain file created for the test run, so
they never touch the login keychain.

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
The file-based keychain needs none. The price is a handful of `SecKeychain…`
calls — for opening the login keychain by its path, switching user interaction
off, removing an item through its reference, and asking whether the keychain is
locked — that Apple marks as deprecated without offering a replacement; the
build warns about them.

## Looking at the items

- Keychain Access: keychain **login**, search for the kind
  `keychain-touchid secret`.
- `keytap list`.
- `security find-generic-password -s <service> -a <account>` prints the
  attributes without asking; adding `-w` asks for the Mac password.
