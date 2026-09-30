# TBRN

A pocket companion for money and trips. Log what you spend, keep track of what
you're packing, and record where a trip has taken you.

Built with Flutter. Everything is stored on the device — there is no account and
nothing leaves the phone.

<p align="center">
  <img src="tool/icon/backpack.svg" width="96" alt="TBRN icon">
</p>

## What it does

**Transactions**
- Expenses and income, nine built-in categories
- More categories from the Other sheet, or name your own
- Cash or online, per transaction
- Filter to a single day, or a whole month
- Spending broken down by category, by day, by week, and as a running balance

**Trips**
- Start a journey with an origin, destination and a packing list
- A calendar of what you did each day
- Reminders while a trip is active
- **Share a trip's costs**: add the people you went with, say which one you are,
  and record who paid each expense
- A trip summary that reduces the whole trip to the *fewest* payments that clear
  it, with each one tickable
- Export a trip as a JSON file and import someone else's, always after a preview

**Pack**
- Checklists, with suggestions based on where you're going
- Attach a checklist to a trip or a saved place

**Places**
- Saved places with a name, an icon and a trigger radius
- Paste a Google Maps link to fill the coordinates
- Drop a pin at your current location

**Settings** — behind the gear in every app bar, not a fifth tab. Currency,
theme, stored-record counts, CSV export, demo data and the wipe all live there.

## Shared trips

Three people front different things at different places, and at the end nobody
can compute who owes whom. That is the problem this solves — not "divide a bill
by N", which is one subtraction.

```
You   taxi 4000 + lunch 1500       = 5500
Raj   boat 3000 + dinner 2400      = 5400
Sita  groceries 2000 + museum 1000 = 3000
total 13900, three people, fair share 4633.33
Sita pays You 867 · Sita pays Raj 767 — two payments, everyone is even
```

The settlement is plain integer arithmetic in paise, greedy largest-to-largest,
with a deterministic sort so the same trip always produces the same list. Shares
are whole paise that add up to the trip total exactly; when the total does not
divide, the leftover paisa goes to the largest creditor.

A ticked payment records a *key*, never a transaction. A reimbursement is money
coming back for money already spent — counting it as income would inflate income,
the balance, the charts and every budget, while the original expense still
counted in full.

### What it deliberately does not do

- **No server, no accounts, no live sync.** A join-code room with shared live
  state needs a backend and would undo "nothing leaves your phone".
- **No QR codes.** A QR holding only a trip identifier has nothing to resolve it
  on the other end, and costs a camera permission. A short typable code does the
  same job.
- **No per-expense splits.** One payer fronts the amount and the group shares
  equally. Correct for friends, and it keeps the settlement exact.
- **No "I owe them" as a separate direction**, and **no multiple wallets**.

### Known limitations, stated in the app

- Someone who joined late is still split across the whole trip. Fixing it needs
  per-expense participation.
- Deletions do not travel between phones. A re-shared file will never resurrect
  something you deleted here — the app keeps a tombstone so add-only import
  cannot undo you — but it also cannot tell you that a friend removed something.
- The trip code identifies the trip so friends can confirm they are on the same
  one. It syncs nothing and joins nobody to a room.
- A shared file contains everyone's spending. Some people will not want their
  food spending visible to friends.

### How importing behaves

Merging is **by ID only** and **add only**: nothing is ever deleted, overwritten
or duplicated by an import, and the same file imported twice changes nothing.
Every import previews the trip, sender, people, expense count and total first,
and asks which participant you are before it will let you confirm — without that,
the app cannot tell you what *you* owe, which is the only number you want.

## Running it

```bash
flutter pub get
flutter run
```

Build an APK:

```bash
flutter build apk --debug
```

## Before you push anything

`master` is meant to be the last state that passed the full check. Work on a
branch, and only merge once this passes:

```bash
tool/verify.sh
```

It checks formatting, static analysis, the test suite and a debug build. The
test run has a wall-clock limit on purpose — a suite that never finishes is a
failure, not a pass.

```bash
git checkout -b feature/my-thing master
# ...work, committing as you go...
tool/verify.sh                 # must exit 0
git branch archive/$(date +%F)-before-my-thing    # snapshot old master FIRST
git checkout master && git merge --no-ff feature/my-thing
git push origin master feature/my-thing archive/...
```

`master` is always the last state that passed the gate. Snapshot before merging:
once master has moved, the old tip only exists in the reflog.

`tool/verify.sh` also sweeps the Flutter tool's leftover temp files out of the
shared `/tmp` tmpfs. That disk filling up used to fail the suite and the Gradle
build with errors that read like problems with the code.

## Branches

`master` is the current state. The numbered branches are snapshots, one per
feature as it landed, kept so you can check out and see the app at that point.

| Branch | |
|---|---|
| `01-journey-interactions` | journey day sheet and stat tiles |
| `02-add-place` | add place screen, icon picker, map link import |
| `03-category-fixes` | fix duplicated categories in the other screen |
| `04-payment-method` | cash/online payment method on transactions |
| `05-pack-ui-fixes` | duplicate checklist button, demo button wrap |
| `06-trip-packing-list` | packing list editor, month header overflow fix |
| `07-light-mode` | light mode surface ladder — newest fully passing state |
| `08-graphs-wip` | extra charts; suite was hanging, work in progress |
| `archive/<date>-before-<name>` | the master tip immediately before a merge |

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

## Data

Stored locally with Hive as plain JSON in a `Box<Map>`. No type adapters, no
schema version, no migration step — records are read defensively, so a field
added later simply reads back as its default and an older record still loads.
