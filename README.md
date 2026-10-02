# TBRN

![Verify](https://github.com/tbrnsb/TBRN-companion/actions/workflows/verify.yml/badge.svg)

A pocket companion for money and trips. Log what you spend, keep track of what
you're packing, and record where a trip has taken you.

Everything is stored on the device. There is no account, and nothing leaves the
phone.

## Why I made it

The trip splitting is the part worth explaining. Three people front different
things, and at the end nobody can compute who owes whom. Every way I could see of
solving that wanted a shared login, and a shared login wants a server to hold it.
So the arithmetic runs on the phone, and a few decisions follow from that: no
accounts, no sync, and an import that can add records but never delete them.

## What it does

**Transactions**
- Expenses and income, nine built-in categories
- More categories from the Other sheet, or name your own
- Cash or online, per transaction
- Filter to a single day, or a whole month
- Spending broken down by category, by day, by week, and as a running balance
- Budgets, per category and per month
- Search across transactions, and a trash you can put things back from

**Trips**
- Start a journey with an origin, destination and a packing list
- A calendar of what you did each day
- Reminders while a trip is active
- Share a trip's costs: add the people you went with, say which one you are, and
  record who paid each expense
- A trip summary that reduces the whole trip to the *fewest* payments that clear
  it, each one tickable
- Export a trip as a JSON file and import someone else's, always after a preview

**Pack**
- Checklists, with suggestions based on where you're going
- Attach a checklist to a trip or a saved place

**Places**
- Saved places with a name, an icon and a trigger radius
- Paste a Google Maps link to fill the coordinates
- Drop a pin at your current location

## Shared trips

Three people front different things at different places, and at the end nobody
can compute who owes whom. That is the problem this solves, not "divide a bill
by N", which is one subtraction.

```
You   taxi 4000 + lunch 1500       = 5500
Raj   boat 3000 + dinner 2400      = 5400
Sita  groceries 2000 + museum 1000 = 3000
total 13900, three people, fair share 4633.33
Sita pays You 867 · Sita pays Raj 767, two payments, everyone is even
```

Each person's net is what they paid minus their share. Creditors and debtors fall
out of the same list, and the settlement matches the largest creditor against the
largest debtor, largest first, until nothing is left owing. That is at most
*n - 1* transfers for *n* people. Both sides are sorted the same way every time,
so the same trip always produces the same list of payments.

Shares are whole paise that add up to the trip total exactly. When the total
does not divide evenly, the leftover paisa goes to the largest creditor rather
than being lost to a rounding rule nobody can predict.

A ticked payment records a *key*, never a transaction. A reimbursement is money
coming back for money already spent, and counting it as income would inflate
income, the balance, the charts and every budget while the original expense
still counted in full.

### Known limitations, stated in the app

- Someone who joined late is still split across the whole trip. Fixing it needs
  per-expense participation.
- Deletions do not travel between phones. A re-shared file will never resurrect
  something you deleted here, because the app keeps a tombstone so an add-only
  import cannot undo you, but it also cannot tell you that a friend removed
  something.
- The trip code identifies the trip so friends can confirm they are on the same
  one. It syncs nothing and joins nobody to a room.
- A shared file contains everyone's spending. Some people will not want their
  food spending visible to friends.

### How importing behaves

Merging is **by ID only** and **add only**. Nothing is ever deleted, overwritten
or duplicated by an import, and the same file imported twice changes nothing.
Every import previews the trip, sender, people, expense count and total first,
and asks which participant you are before it will let you confirm. Without that
the app cannot tell you what *you* owe, which is the only number you want.

## Settings

The gear in the app bar, not a fifth tab.

- **Appearance**: theme, brightness, and number format
- **Money**: currency, and budgets
- **Categories**: add to the built-in nine, or name your own
- **Stored on this device**: a count of everything held, plus CSV export and
  import
- **Deleted**: trashed transactions, which can be put back
- **Demo data**: add a month of labelled sample records, or clear them again

## Installation

Android only. Built and tested against Flutter 3.47.0 on the stable channel and
Dart 3.13.0.

```bash
git clone https://github.com/tbrnsb/TBRN-companion.git
cd TBRN-companion
flutter pub get
```

To run it on a connected device or emulator:

```bash
flutter run
```

To build an APK:

```bash
flutter build apk --release
```

That writes `build/app/outputs/flutter-apk/app-release.apk`. Copy it to the
device and open it, or install it over ADB with `adb install`.

## Privacy

All data is stored locally on your device. No accounts, no server, no cloud sync.
Nothing leaves your phone.

There are no network calls in the app and no analytics. Two things do hand data
to other apps, and only when you ask: sharing a trip or a CSV goes through the
Android share sheet, and opening a saved place hands its coordinates to whichever
maps app you have. Android's own cloud backup is switched off in the manifest, so
the system will not copy your data to a Google account either.

## Data & backups

Records are stored with Hive as plain JSON in a `Box<Map>`. No type adapters, no
schema version and no migration step. Records are read defensively, so a field
added later reads back as its default and an older record still loads.

**Transactions, one month at a time.** Settings has *Export this month as CSV*,
which writes `transactions-YYYY-MM.csv` and hands it to the Android share sheet.
*Import transactions from CSV* reads one back. Both act on the month you are
looking at, so exporting each month in turn is how you keep a full history.

**Trips.** Open a trip, then its summary, and *Share* writes the whole trip to a
JSON file. *Import someone else's file* on the same screen reads one, and it
previews the trip and asks who you are before it writes anything.

**Everything else.** Checklists, journeys, places, budgets and custom categories
have no export of their own. They live in the app's own storage, so uninstalling
the app removes them, and the trip JSON is the only way to move a journey to
another phone.

## Contributing

Run `tool/verify.sh` before every commit. It checks formatting, static analysis, the
test suite and a debug build, and it must exit 0.

## Layout

```
lib/
  models/         plain data classes, Hive JSON
  providers/      app state
  screens/        one directory per tab
  services/       storage, notifications, CSV export
  theme/          colours, spacing, type scale, surfaces
  widgets/        shared UI
test/
tool/
  icon/           launcher icon source
  verify.sh       the pre-merge gate
```

Licensed under the MIT License. See [LICENSE](LICENSE) for details.
