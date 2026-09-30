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

**Pack**
- Checklists, with suggestions based on where you're going
- Attach a checklist to a trip or a saved place

**Places**
- Saved places with a name, an icon and a trigger radius
- Paste a Google Maps link to fill the coordinates
- Drop a pin at your current location

**Settings** — behind the gear in every app bar, not a fifth tab. Currency,
theme, stored-record counts, CSV export, demo data and the wipe all live there.

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
git checkout -b feature/my-thing
# ...work...
tool/verify.sh                 # must exit 0
git branch archive/$(date +%F)-before-my-thing
git checkout master && git merge --no-ff feature/my-thing
```

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
