# Changelog

Notable changes to this project. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-10-14

A bug-fix and small-features release. Nothing here breaks existing data: every
record written by 1.1.0 loads exactly as it did, and no storage format changed.

### Fixed

- **Notifications were dropped in silence on Android 13 and newer.** Those
  versions require an app to ask permission before it may show a notification,
  and the app never asked — so every arrival alert, trip reminder and budget
  alert was discarded by the system before it appeared, while the per-place
  toggle read ON the whole time. The permission is now requested, so an alert
  you can switch on is an alert that can reach you.
- **Turning on a place's alerts did not ask the phone for permission.** Only
  the Settings page ever put the request on screen, so a place switched on from
  its own screen could read enabled on a phone that had never been asked. The
  first switch-on now asks.
- **Settings could report a phone with notifications ON as "Off"** — and never
  looked again. The row read the permission once and kept that answer for as
  long as the screen stayed up, and a read that timed out was painted as a
  plain "Off", indistinguishable from alerts really being blocked. It now tells
  "Unknown" from "Off" and lets you check again.
- **A solo trip could never be made shared again.** The one control that could
  do it, "This trip is shared after all", sat inside the shared section — which
  drew nothing at all for a trip declared solo — so the flag set at creation
  could not be undone from anywhere in the app. A solo trip now gets that
  control.
- **The per-place notification switch did not redraw.** The tap was saved, but
  the switch kept showing its old state, so a place you had just turned ON
  still read OFF until something else redrew the screen.
- **"Clear packed items" deleted every ticked item with one mis-tap.** It was
  the only destructive action in the app that did not ask first, and it cannot
  be undone. It now asks.
- **Ending a trip whose id matched nothing ended whichever trip happened to be
  running.** A stale screen, a trip already ended elsewhere, or one deleted
  since could close an unrelated journey with no error and no undo. An id that
  matches nothing now ends nothing.
- **Deleting a trip did not promote another running trip.** The active-trip
  slot was merely cleared, so with another unfinished trip still on the list
  the app went quiet — no active card, no "Heading home?" prompt, no reminders
  — for a trip that was genuinely under way. The slot is recomputed now, and
  the other trip is picked up.
- **Income categories were still offered when adding an expense.** The first
  pass cleaned the pickers but not the history-derived "Recent" row, which
  brought its own mixed list to the top of the sheet — so a row could still be
  filed on the wrong half of the ledger by the shortest route on the screen.
- **The colour picker's "stops offering colours already in use" rule removed
  nothing.** The built-in colours and the swatch list did not overlap, so
  nothing was ever filtered out and the income and expense grids came out
  identical. The grid now differs by kind, and colour names no longer repeat —
  eleven colours were called "orange", and the swatch the palette calls amber
  was labelled "orange".
- **Journeys could not be deleted at all.** A trip you were finished with had
  no way off the phone.
- **A journey that owned a real checklist listed its items twice** — tickable
  on the trip's own screen, and again as untickable chips on the checklists
  list, where the same bag appeared packed in one place and not the other.
- **The checklist's per-item delete button had no accessible name**, four
  icon-only controls drew 40x40 hit boxes where 48x48 is the standard, and
  lists that reorder were rebuilt without keys — so items could jump when they
  moved.
- **A packing list typed while creating a journey never appeared in the Pack tab.**
  Items written while starting a trip were kept as plain text on the journey, with
  no ticks and no place in the Pack tab, and the trip's own "Pack for this trip"
  button stayed on screen for good — tapping it answered "Already packed for this
  trip" to someone who had never been able to tick anything. A journey created
  with items now gets a real checklist in the same breath as the journey.
- **Your own checklists sat below two decorative cards.** The location reminder and
  everyday essentials rendered above "All Checklists", so a packed journey looked
  like its list was missing. Your lists come first now.
- **A custom category saved as Income was offered when adding an Expense.** The
  two lists were flattened into one before the pickers ever saw them, so a row
  could be filed on the wrong half of the ledger — which then misreported the
  balance, the charts and every budget while looking right.
- **Renaming a category did not reach the transaction history.** Past transactions
  kept reading the old name while the picker offered the new one, and searching for
  the new name could not find the old rows. Categories now carry the names they
  were previously called, so history follows a rename. Nothing is rewritten and no
  transaction is migrated.
- **Adding a transaction could take ten seconds.** The save was queued behind a GPS
  fix and a proximity question. The row is written first and the coordinates
  backfilled, so the ledger updates immediately and a fix that never arrives costs
  only a missing pin.
- **Four palettes shipped a card tier identical to the page colour.** In Catppuccin
  Latte, Gruvbox, Solitude and Catppuccin Mocha, `surfaceMid` was the page colour
  itself, so the Budgets, Journeys and Active Journey cards rendered as nothing.
- **The same name could not be an expense category and an income category.** The
  second was silently refused, leaving the income side pointing at the expense
  record.
- **A running journey read as "0m".** Its duration only counted once the trip had
  ended, so every active trip showed a precise-looking wrong answer and the running
  total across journeys under-reported by however long you had been away.

### Added

- **"Heading home?"** Replaces "Complete journey". It walks your packing list,
  lets you tick it off, and ends the trip — blocked while anything is unticked,
  with an explicit "End anyway" rather than a silently disabled button.
- **Journey durations count up while a trip is open**, and read in days, so a
  week is "7d 2h" rather than "168h 0m".
- **A journey can be declared solo** at creation. The shared block does not
  disappear — it draws its "Shared" header with "Solo" beside it, one line
  saying there is nothing to split and nobody to add, and the single control
  "This trip is shared after all", which turns sharing back on. What stays
  hidden is the roster, the add field and the splitting UI, because those
  belong to a trip that is going to be shared. The start-trip checkbox reads
  "Nobody to add, nothing to split."
- **Arrival notifications, per saved place.** You are told when you reach a place,
  at a 1 km radius rather than the place's own tighter one. On by default, and
  switchable per place.
- **A Settings row that says whether the phone will show this app's alerts.**
  It reads the permission rather than assuming it, and when alerts are blocked
  it opens the system settings page — the only place they can be switched back
  on.
- **"Where to?" on a travel expense.** Free text, so a taxi fare can name a
  destination you never saved as a place — which is what makes "what did getting
  to SmatErr cost" answerable.
- **A journey's start time can be corrected.** A trip planned for nine that left
  at eleven was wrong for good, with no way to tell it apart from one that really
  did leave at nine.
- **The custom category colour picker stops offering colours already in use** —
  any built-in of that kind, and any other custom category of that kind. The same
  colour is still allowed on income and expense, since those are separate charts.

### Removed

- **The packing suggestions.** They matched the destination against a keyword
  list, so a trip called "SmatErr" matched nothing and received the same eight
  generic items every unrecognised name received. They also rendered above your
  own list, which is part of why a packed trip looked unpacked.

## [1.1.0] - 2026-10-04

Nothing in this release breaks your existing data. Every record written by 1.0.0
loads exactly as it did, and the app's storage format is unchanged.

### Added

- **Every transaction now remembers where you were.** Latitude, longitude and the
  time the reading was taken are saved with the transaction — whether or not you
  have ever named that spot.
- **Income records its location too.** Money arriving somewhere is recorded the
  same way money leaving it is. Before this, only expenses carried a position, so
  a place you were paid at was invisible to everything that reads a location.
- **"Are you at [place]?"** When a transaction lands inside the radius of a place
  you have saved, the app asks whether to link it. Say yes and the two are
  counted together; say no and it keeps its own coordinates, and you are not
  asked again about that place for a while.
- **"You have been spending here a lot."** After four transactions near a spot you
  have not named, the app offers to save it as a place. It opens the same Add
  Place form you already know, with the coordinates filled in — you are only asked
  what to call it.
- **Saved places have a screen of their own.** Tapping a place shows how many
  transactions happened there, how much you spent and received, a breakdown by
  category, and the full history — each row opens the transaction.
- **Everything links to everything.** Tap a place name on a transaction to see
  everything recorded there. Tap a journey to open the trip. The history on a
  place opens the transaction. Previously those names were text and led nowhere.
- **Open in Maps from a transaction**, for any transaction that carries a
  position.
- **Twenty themes across four families**, up from a handful — including a full
  Gruvbox palette with its own second accent colour.
- **Budget periods.** A limit per category and per trip, each over a week, a
  month, or a year.
- **Search has its own screen**, filtering by description text, amount range and
  category.
- **Trash.** Deleting a transaction is now reversible.
- **CSV import**, the reverse of the export already in Settings. Rows are
  previewed before anything is added.

### Fixed

- **"Open in maps" never worked on Android 11 or newer.** The app had not told
  Android which map schemes it wanted to use, so the system refused to say which
  apps could handle them. It reported "no maps app found" on a phone with Google
  Maps sitting on it.
- **A place with an ampersand in its name lost its label** on the map pin. The
  name was pasted into the link without escaping, so a place called "Cafe & Bar"
  arrived with only "Cafe " on it.
- **Transactions were recording no location at all on most phones.** The reading
  required the "Allow all the time" permission, but Android's normal grant is
  "Allow while using the app" — so on the great majority of devices the capture
  quietly did nothing. This is why places had nothing recorded against them.
- **Custom income categories could not be chosen.** They were saved correctly, but
  the income form only ever listed the six built-in categories, so a category you
  had added in Settings simply was not there to pick.
- **"You have been spending here a lot" never appeared.** It was counting
  distinct *days* rather than transactions, so five expenses recorded in one
  sitting counted as a single day against a threshold of four.
- **An unrelated filter could silence that prompt.** Leaving "Income" selected
  hid every expense from the count, and picking a day in the calendar narrowed the
  count to that day — either stopped the prompt appearing, with no visible reason.
- **The heatmap had no weekday labels.** Seven columns of coloured squares with
  nothing to say which was Monday was a texture, not a calendar.
- **Chart pages could draw over their own headings** at larger text sizes, and
  the running balance chart left a gap underneath.
- **The Settings page had three different row heights**, so it never looked like
  one list.
- **Search results could get stuck.** Search for something that matched nothing,
  then go back, and the transaction list stayed empty with no way to undo it.
- **Category colours looked pasted on.** They were tuned against a single light
  palette and looked wrong on the others. They are now re-derived for whichever
  surface they are drawn on, and the closest pair of greens was pulled apart so
  Gear and Freelance can be told apart.

## [1.0.0] - 2026-10-02

### Added

- Shared trip expenses. One payer fronts a cost, everyone shares it, and the app
  works out the fewest payments that settle the trip up.
- Income and expense transactions, in categories you can add to or name yourself.
- Packing checklists, with suggestions based on where you are going.
- Local storage with Hive. No account, no server, no sync.
- CSV export, from Settings.

### Fixed

- The calendar shows the month you are actually looking at.
- A day in the past can be picked.
- Charts no longer leave an empty gap underneath them.
- The bottom dock follows the palette you pick, instead of staying on one theme.
