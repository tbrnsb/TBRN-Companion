# Changelog

Notable changes to this project. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[semantic versioning](https://semver.org/spec/v2.0.0.html).

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
