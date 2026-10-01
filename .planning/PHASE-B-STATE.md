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
