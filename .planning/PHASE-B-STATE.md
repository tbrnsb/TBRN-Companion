# PHASE B STATE

Append-only. A fresh window resumes from the last line that says MERGED.

## STAGE STATUS

```
PHASE B ITEM STATUS
[x] 1.  Shared-trip ledger filter   fix/shared-trip-ledger-filter   MERGED 36df86f
[ ] T1. Theme families + settings  fix/theme-families-and-settings
[ ] T2. Secondary text contrast    fix/secondary-text-contrast
[ ] 2.  Demo data dates            fix/demo-data-dates
[ ] 3.  Duplicate add buttons      fix/duplicate-add-buttons
[ ] 4.  Jump-to-day no-ops         fix/jump-day-noops
[ ] 5.  Heatmap month shape        fix/heatmap-month-shape
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
