# PHASE B STATE

Append-only. A fresh window resumes from the last line that says MERGED.

## STAGE STATUS

```
PHASE B ITEM STATUS
[x] 1.  Shared-trip ledger filter   fix/shared-trip-ledger-filter   MERGED 36df86f
[x] T1. Theme families + settings  fix/theme-families-and-settings MERGED 2de8620
[x] T2. Secondary text contrast    fix/secondary-text-contrast     MERGED a818595
[x] 2.  Demo data dates            fix/demo-data-dates             MERGED b8387f8
[x] 3.  Duplicate add buttons      fix/duplicate-add-buttons       MERGED a645bf9
[x] 4.  Jump-to-day no-ops         fix/jump-day-noops             MERGED 6725875
[x] 5.  Heatmap month shape        fix/heatmap-month-shape        MERGED 9db50a7
[x] N1. Heatmap cell size + shape  fix/heatmap-cell-size       MERGED 2be8247
[x] N2. Budget period limits       fix/budget-period-limits    MERGED 404a507
[ ] N3. Month navigation           fix/month-navigation
[ ] N4. Search youtube view        fix/search-youtube-view
[ ] 6.  Chart pager blank page     fix/chart-pager-blank-page
[ ] 7.  Chart design system        fix/chart-design-system
[ ] 8.  Date picker bounds         fix/date-picker-bounds
[ ] 9.  Global calendar icon       fix/global-calendar-icon
[ ] 10. Category contrast verify   fix/category-contrast-verify
[ ] 11. Testing standard           fix/testing-standard
```

## MERGED OUTCOMES

### Item 1 — shared-trip ledger filter — MERGED `36df86f`
Branch `fix/shared-trip-ledger-filter`, tagged `snapshot-fix/shared-trip-ledger-filter`,
archive `2026-10-01-before-ledger-filter`, pushed. **610 → 633 tests (+23)**, gate green.

**THE SPLIT-BRAIN, measured.** `spendIndex` already applied the shared-trip rule,
`_viewTransactions` returned the raw month, so for September the summary card read
**21070.50** while the budget beside it read **12670.50**.

| month | raw storage | others' trip | view before | view after | drop |
|---|---|---|---|---|---|
| 2026-08 | 7170.50 | 0.00 | 7170.50 | 7170.50 | 0.00 |
| 2026-09 | 21070.50 | 8400.00 | 21070.50 | **12670.50** | **8400.00** |
| 2026-10 | 450.50 | 0.00 | 450.50 | 450.50 | 0.00 |

Raw storage did NOT move. The change is **view-side only**.

Sept ledger per category: food 3350.50, travel 4640, gear 1500, housing 2450,
health 320, utilities 410.

**THE FIX.** `TransactionProvider.myLedger` is the single filtered view;
`_viewTransactions`, `searchResults` and `spendIndex`'s loaded-month branch all
read it. A computed property, not a cache.

**DECISIONS MADE (do not re-litigate).**
- `daysWithTransactions` does NOT mark a day holding only other people's trip
  spending — tapping it would show an empty list.
- **Income is unaffected**: `Income` has no `journeyId`/`paidByParticipantId`, so
  the predicate counts it. The filter has no effect on the income side.
- Journey budgets ARE filtered (1800 not 3000). My Stage 7 comment said "whoever
  paid"; the code did the opposite and the code was right. Comment corrected.
- Settlement/trip summary deliberately UNFILTERED, asserted byte-identical.

**TWO PRE-EXISTING BUGS THE FIX EXPOSED, both fixed.**
- `locatedExpenses` did `as List<Expense>` on a `List<Transaction>` — a RUNTIME
  crash. Rebuilt with `whereType<Expense>()`.
- `statusesFor` took `List<String> journeyLabels` and searched it for a label,
  which could only find the label — so every trip budget was titled with its raw
  id. Now `Map<String,String>`.

**PERMANENT SEAMS.**
- `test/spending_baseline.dart` has extension `ViewTotalForMonth.on
  TransactionProvider` — navigates and reads `totalExpenses`. Lives in test/ so
  lib/ ships no mutating test-only method. Re-run it after any data change.
- The split-brain guard is a provider test in `test/ledger_filter_test.dart`:
  `totalExpenses == spendIndex().total`.

**FOR THE NEXT AGENT.** `spending_baseline.dart` prints three figures per month:
raw storage, ledger (`spendIndex`) and view (`totalExpenses`). All three must
agree except that raw includes others' trip spend. If raw moves, the DATA changed.
If only view moves, the view changed. Say which.

### T1 — theme families + settings — MERGED `2de8620`
Branch `fix/theme-families-and-settings`. **633 → 661 tests (+28)**, gate green.
Kanagawa REMOVED exhaustively: enum, spec, name, tagline, and every comment
using it as a live example (all rewritten to name Gruvbox). 4 families.

**Migration table — legacy int → meant → now restores:**

| int | meant | restores |
|---|---|---|
| 0 | tbrn | tbrn |
| 1 | kanagawa | tbrn (default, no throw) |
| 2 | solitude | **solitude** |
| 3 | gruvbox | **gruvbox** |
| 4 | catppuccin | catppuccin |

Stored by NAME now; legacy int read once through a LITERAL table and removed.
The name key is `theme_palette_name` — a DIFFERENT key from the legacy
`theme_palette`, because `getString` on an int key throws.

**Theme/brightness spec count: 6** (2 light + 4 dark). Was 7 with Kanagawa.
The Stage 10 report's "nine" was wrong; counted in code.

**BUG FOUND: `load()`'s absent theme-mode fallback was `2`, which is
`ThemeMode.dark`.** The documented `ThemeMode.system` default was overwritten
before the first frame on EVERY launch. Now `ThemeMode.system.index`. A stored
2 is still honoured as dark.

Currency and ThemeMode remain INDEXED on purpose — their enums are not changing.

Settings restructured: ONE "Themes" section FIRST, family → variant, live
preview, Light OMITTED (not disabled) for the dark-only families. "Colours"
string is gone from lib/.

### T2 — secondary text contrast — MERGED `a818595`
Branch `fix/secondary-text-contrast`. **661 → 669 tests (+8)**, gate green.

`onSurfaceVariant` was `isDark ? spec.outline : spec.secondary`. `outline` is a
BORDER token. Measured 1.78–2.68:1 on the four dark specs. Now computed, mixed
toward the palette's own `onSurface` until it clears. **Floor 4.5:1** (body copy).

| spec | surface | container | containerHigh |
|---|---|---|---|
| tbrn light | 6.14 → 6.14 | 5.78 → 5.78 | 5.38 → 5.38 |
| tbrn dark | 2.68 → 7.80 | 2.58 → 7.51 | 2.44 → 7.12 |
| solitude dark | 2.32 → 6.74 | 2.24 → 6.50 | 2.12 → 6.15 |
| gruvbox dark | 2.41 → 8.70 | 2.26 → 8.16 | 1.78 → 6.42 |
| catppuccin mocha | 2.63 → 9.08 | 2.46 → 8.48 | 1.88 → 6.50 |
| catppuccin latte | 3.47 → 5.51 | 3.31 → 5.27 | 3.08 → 4.90 |

TBRN light already passed and is deliberately UNTOUCHED.

**The two 0.35 alphas, measured as composited colours:**
- Pager dots: 0.35 → 1.63:1 (cream). Set to **0.75**, lowest clearing 3:1 in all
  six specs. Constant `ChartPager`'s `inactiveDotAlpha`.
- Trend card highlight: NOT an alpha problem — a whole different colour. Now
  `_nudgeTowardInk`, moved the least amount that clears 3:1 against the card.

**Per-site verdict:** every one of ~70 `onSurfaceVariant` reads across 25 files
is body copy or an icon. NONE is decorative-quiet, so NONE needed a quieter
token. Only non-text sites: pager dots (fixed) and `spending_map.dart:46` icon
(correct at the new token).

### Item 2 — demo data dates — MERGED `b8387f8`
Branch `fix/demo-data-dates`. **669 → 676 tests (+7)**, gate green.

`DateTime(y, m, now.day - n)` clamped to `1..now.day` collapsed every record
onto day 1 early in a month. Now day is a POSITION in the month, capped at today.
Amounts made lumpy (was: a few large, many identical small).

**Baseline after item 2** (August and September unchanged):
- 2026-08 — 7170.50, split-brain 0.00
- 2026-09 — 12670.50, split-brain 0.00
- 2026-10 — **450.50 → 4126.75**, split-brain 0.00

**Item 1's September verification STILL HOLDS** (12670.50, others 8400.00).

### Item 3 — duplicate add buttons — MERGED `a645bf9`
Branch `fix/duplicate-add-buttons`. **676 → 680 tests (+4)**, gate green.

RULE (a) decided once: FAB hidden while empty, EmptyState carries the action.
Fixed `transactions_screen` and `locations_screen`.
`checklists_screen` was flagged as possibly INVERSE — it is NOT; `isEmpty ?
null : FAB` is rule (a) already applied correctly.

FAB condition reads the MONTH not the search result. Stage 6 search empty state,
Stage 7 budgets, Stage 8 trash and Stage 9 import preview all have NO FAB at
all, so none can double up.

`test/spend_screen_test.dart` gained `tapAddAffordance`, which taps the FAB if
present else the EmptyState's button.

### Item 4 — jump-to-day no-ops — MERGED `6725875`
Branch `fix/jump-day-noops`. **680 → 692 tests (+12)**, gate green.

`DayPick` — THREE explicit outcomes (`dismissed`, `wholeMonth`, `day`) instead
of a nullable DateTime. Only `wholeMonth` clears the filter.
`setSelectedDay` returns `DaySelectionOutcome`; every refusal becomes a snack bar.

**CRASH FOUND BY THE TESTS:** the picker's `lastDate` is capped at today, so a
selected day past today made `initialDate` LATER than `lastDate` and the sheet
ASSERTED on open. Fixed at the provider (a future day is refused, with
`DayInTheFuture`) and `initialDate` is clamped regardless.

Confirmed by test, not assumption: changing month clears a stale day filter, in
the provider AND through the UI's month arrows; the pager keeps its height
across a day toggle.

### Item 5 — heatmap month shape — MERGED `9db50a7`
Branch `fix/heatmap-month-shape`, tag `snapshot-fix/heatmap-month-shape`.
**692 tests**, gate green. Follow-up commit `44bfc72` on master.

**PROCESS ERROR, self-reported:** item 5's commit went STRAIGHT ONTO master with no
branch, no archive and no tag, because I was still on `fix/jump-day-noops` and
checked out master without creating the branch first. Recovered by pointing the
branch and tag at the merge-less commit. The code is right and gated; the
bookkeeping was wrong.

**Also: two files from ALREADY-MERGED items were left unstaged** —
`app_chart_colors.dart` (T1's Kanagawa→Gruvbox comment rewrites) and
`spend_screen_test.dart` (item 3's `tapAddAffordance`). Both were part of green
gates. Committed as `44bfc72` rather than amending a published commit.

**WHAT CHANGED**
- `weeksIn` returned a fixed 5 under 520dp → a 6-week month lost a week of
  VISIBLE DAYS. Now `columnsForMonth(y, m) = ceil((leadingDead + daysInMonth)/7)`,
  clamped to 4..6. **6-week decision: draw 6, cells shrink. Never truncate.**
- `crossAxisAlignment: start` + content-sized rows DISCARDED the leftover width.
  Now `stretch` + `Expanded` cells, square via `AspectRatio`, so the grid fills
  the card at both viewports.
- Title now names the month and year, derived from the data.
- Legend uses `rampLength` not a literal `/4`.

**Stage 10 tokens used — NO second red:** `AppChartColors.spendRamp(scheme)`,
`spendStep(scheme, i/(rampLength-1))`, `rampLength(scheme)`,
`heatmapEmpty(scheme)`, `heatmapDead(scheme)`. `_shade()` and the
`primary`-at-0.22 tint are GONE and must not come back.

**Zero-max decision:** `spendStep` returns `heatmapEmpty` at intensity 0 and
`intensity` is `0.0` when `busiest <= 0`, so there is no divide and no
divide-by-zero. A month of only other people's trip spend (after item 1) has
`busiest == 0` and renders every day as the EMPTY cell — never a divide.

**Empty-day-picker decision (item 1):** a day holding only other people's trip
spending is NOT marked in `daysWithTransactions`.

**STOPGAP FLAGGED FOR ITEM 6:** pager height 268 → 640, because a width-filling
square grid is tall and 268 clipped it by 361px. ONE height for four pages sized
for the tallest, so the Daily/Balance/Weekly pages now carry large dead space.
Item 6 must replace the fixed height with a per-page one.

### N1 — heatmap cell size and shape — MERGED `2be8247`
Branch `fix/heatmap-cell-size`, tagged `snapshot-fix/heatmap-cell-size`,
archive `2026-10-01-before-heatmap-cell-size`, pushed. **692 → 702 tests (+10)**,
gate green (analyze, format, 702 tests, debug APK).

**ITEM 5 WAS THE TRANSPOSE, NOT A SHAPE BUG.** It drew five week-COLUMNS by
seven weekday-ROWS — days running down the screen and weeks running across it.
That is the transpose of a calendar, which is why the grid read as "a random
throwing of pixels" and not as a month. The row count was right; the AXES were
swapped.

Measured at 412x915, on the transposed grid:

| what | item 5 | N1 |
|---|---|---|
| grid shape | 5 columns x 7 rows | **7 columns x 4–6 rows** |
| cell size | ~45px (Expanded + AspectRatio) | **11px** (`SpendingHeatmapShim.cell`) |
| row height | ~7 x 45 + gaps | **15px** |
| grid height | ~315px | **under 100px** |
| day-to-day step | vertical | **66.8px horizontal** |
| row span | n/a | **412px, full card** |

The month decides the shape, not the window:
`rowsForMonth = ceil((leadingDead + daysInMonth) / 7)`, clamped 4..6.

**A SIX-WEEK MONTH WAS LOSING A DAY.** November 2026 opens on a SUNDAY, and
`weekday` is 7 — so leading dead is SIX, not zero, and 6 + 30 = 36 cells needs
six rows. Reading a Sunday as "no leading space" turns a six-week month into
five and drops a visible day. May 2027 (5 leading + 31) is the same trap.
`six-week months draw every day of the month` asserts day 31 is painted.

**THE EMPTY AND DEAD TOKENS WERE SURFACE COLOURS.** `heatmapEmpty` was
`surfaceContainer` and `heatmapDead` was `surfaceContainerLowest` — the two
lowest-contrast steps in the ladder, built to sit behind content almost
invisibly. A day with no spending was nearly the colour of the card it sat on,
so the grid had no visible rectangle at all. Both are now INK, mixed toward the
palette's own `onSurface` and searched until the MEASURED contrast against the
card clears its floor. Not 3:1 and not 4.5:1: these are grid structure, and
either of those bars makes a month-shaped block of grey compete with the
spending it frames.

| spec | empty | dead |
|---|---|---|
| TBRN light | 1.61:1 | 1.20:1 |
| TBRN dark | 1.60:1 | 1.20:1 |
| Catppuccin light | 1.61:1 | 1.20:1 |
| Catppuccin dark | 1.60:1 | 1.20:1 |
| Solitude dark | 1.60:1 | 1.20:1 |
| Gruvbox dark | 1.60:1 | 1.20:1 |

`structureFloor` 1.6 for empty, `deadFloor` 1.2 for dead — dead is fainter, so
the month's outline reads, but neither is invisible and the two are never the
same colour. Dead has its OWN floor because a single floor resolved them to
1.6051:1 and 1.6061:1 on TBRN light: indistinguishable, which is the original
bug arriving through the front door.

Both tokens are asserted twice — once as maths across all six specs, once read
back out of the RENDERED widget tree — because a token that is right but never
painted is still invisible.

**spaceBetween IS NON-NEGOTIABLE.** Content-sized rows DISCARD the leftover
width and the grid hugged the left, which is item 5's real fix. Expanded also
decides the width, so item 5 resolved the hug by making the cells huge. Fixed
cells plus `spaceBetween` keeps both: seven 11px cells, even gutters, full
card. `cellFor` has no width term at all.

`_shade` and `primary` at alpha 0.22 do not come back. Tooltips, the highlight
border, `rampLength(scheme)` and the zero-max rule are unchanged.

**TWO OF THESE TESTS WERE WRONG ABOUT THE GRID BEFORE THEY WERE WRONG ABOUT THE
CODE.** Both measured "day 1 to day 7" as a row; in a month with leading dead
space that spans two rows. The row is now DERIVED from `leadingDead`, and both
tests assert the leading count first so a future wrong month fails as a wrong
month rather than as a mystery spacing failure.

The pager is still 640. N1 makes the heatmap small again; item 6 replaces the
fixed height with per-page measured heights.

### N2 — budget period limits — MERGED `404a507`
Branch `fix/budget-period-limits`, tagged `snapshot-fix/budget-period-limits`,
archive `2026-10-01-before-budget-period-limits`, pushed. **702 → 715 tests (+13)**,
gate green (analyze, format, 715 tests, debug APK).

**THE STORAGE KEY DID NOT SAY WHICH PERIOD A LIMIT WAS FOR.** It read
`budget_limit_cat:food` and held ONE number, so setting a weekly food limit
replaced the monthly one and only whichever was written last was ever readable.
A weekly and a monthly food budget are different numbers answering different
questions, and the store was treating them as one slot.

Keys are now `cat:<name>:<period>` and `trip:<id>:<period>`, parsed in one place
(`BudgetKey`) so a key written here and read there cannot disagree. A period-less
key parses as LEGACY and reports month, because month was the only period that
ever existed here. A segment that is not a period is REJECTED rather than guessed
at: a corrupt key reported as a real budget is worse than a key ignored.

**THE MIGRATION, ONCE.** `load()` rewrites a period-less limit onto `:month` and
REMOVES the old key, so the migration cannot run twice and cannot leave a shadow
copy that a later write would resurrect. Categories and trips both migrate —
leaving trip limits on the old key would orphan every trip limit the user had set.
An unparseable key is left ALONE, because it might belong to a version this build
cannot read, and deleting it would destroy a limit for no gain.

Two consequences that were separate bugs and are now one:

- `statusesFor` and `notifyCrossed` read ONLY the budgets for the index's period.
  With a weekly and a monthly limit on Food both present, reading every budget
  against one period's spending judged each against the wrong figure.
- `BudgetStatus.storageKey` includes the period. It de-duplicates notifications,
  and with a period-less key this week's crossing was suppressed as a duplicate
  of this month's: the user was told about it once, ever.

**THE SCREEN ASKED NINE QUESTIONS AT ONCE.** It listed every category with its own
bar and no subject — a dashboard, where the one category that matters is
impossible to find. Now:

| | before | after |
|---|---|---|
| period control | a small chip row, labelled "Period" | **full-width SegmentedButton, above the fold** |
| range | on the same line as the total | **its own line, from `BudgetPeriodX.window`** |
| category | every category, each with a bar | **ONE dropdown** |
| subject | none | **one reading** |
| total | in the range line | **its own line, as context** |
| trips | a full section above the fold | **counted disclosure, below the fold** |

TWO category controls would be one too many, so there is a dropdown and NO chip
row — asserted directly, because the two are easy to reintroduce by accident.
Switching period KEEPS the category: the category is the subject and the period
is the lens, and re-reading the same food budget through week and month is the
comparison a user actually makes. The window is never recomputed on the screen.

Trips remain period-aware and reachable: tapping the disclosure opens them, and a
collapsed section carries its count so it is not indistinguishable from an empty
one.

**Two of the new tests were wrong before they were right.** The migration
fixtures wrote `4500` and expected `4500` back, which would also have passed
against a provider that ignored hundredths entirely — stored values are in
hundredths, so 4500 rupees is `450000`. And the old "every category has a row"
assertion had no way to express WHICH category was the subject, which is the
entire point of the change.
