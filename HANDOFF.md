# TBRN — handoff notes

Read this first. It is the state of the project as of the last session, written
so a fresh agent can continue without rediscovering anything.

- Repo: `/home/sulav/Documents/flutter_application_1` (git, branch `master`)
- Last commit: `f4cb447` "fix: give light mode an actual surface ladder"
- Backup of that same state: `backup/tbrn-all-commits.bundle` (verified
  complete history; restore with
  `git clone backup/tbrn-all-commits.bundle restored-repo`)

---

## 0. FIRST JOB — finish what is already applied. Do not add anything new yet.

**The working tree does not currently pass its own test suite. Fix that before
writing a single line of new feature code.**

Seven features are applied and committed. The graph work is applied but
**uncommitted and not green**. The next session's first task is to get back to a
fully passing suite, commit the graph work, and only then start anything from
section 4. Adding features on top of a hanging suite buries the hang.

### The known hang

`flutter test` (full suite) hangs indefinitely. Reproduce with:

```bash
cd /home/sulav/Documents/flutter_application_1
timeout 150 flutter test --reporter=failures-only; echo "exit=$?"
```

`exit=124` means the timeout killed it — that is the hang, not a slow run.

What is already known about it:

- At commit `f4cb447` the suite passed in ~14s (238 tests). The hang was
  introduced by the **uncommitted** graph work only.
- `test/spend_screen_test.dart` was one confirmed hang site: the test
  `category breakdown charts / the Expenses filter shows only the spending
  chart` never completed. That one was caused by
  `FlGridData(horizontalInterval: gridStep)` — telling fl_chart to step the axis
  by a fixed interval makes it walk in ever-smaller increments when the interval
  does not divide the range evenly. It now draws a fixed set of lines via
  `checkToShowHorizontalLine` / `_isAtFractions(...)` instead, and
  `test/spend_screen_test.dart` and `test/day_filter_test.dart` pass (32 tests).
- **A hang remains elsewhere in the suite and is NOT yet isolated.** Run each test
  file on its own to find it:
  ```bash
  for f in test/*_test.dart; do
    printf '%s: ' "$f"
    timeout 90 flutter test "$f" --reporter=failures-only >/dev/null 2>&1
    echo "exit=$?"
  done
  ```
  `exit=124` is the hanging file.
- Remaining suspects in the uncommitted diff, in order of likelihood:
  1. `CumulativeBalanceChart`'s new `extraLinesData` dashed zero line — a
     `HorizontalLine` outside the plotted `minY`..`maxY` range can confuse
     fl_chart's axis sizing.
  2. Its new `bottomTitles` with `interval: 1`.
  3. The new `WeeklyTotalsChart`, which is now rendered by
     `transactions_screen.dart` and so appears on every screen that shows the
     charts.

If the hang proves hard to isolate, the safe move is to `git checkout` the two
uncommitted files (the patch is in `backup/uncommitted-charts.patch`) and redo
the graph work in smaller, individually tested steps. Nothing else depends on it.

### Also outstanding in the applied work

- The graph work has **no tests of its own**. No chart test file exists. Copy the
  harness from `test/phone_layout_test.dart` or `test/day_filter_test.dart`;
  `test/test_viewports.dart` has `TestViewports.phonePortrait` (412x915) and
  `phoneSmall` (360x640), and `usePhoneLayout` installs an `OverflowWatch` that
  fails the test on any overflow.
- `analysis_options.yaml` now excludes `backup/**`. The backup folder holds real
  copies of two source files; without the exclusion `flutter analyze` tries to
  compile them and reports a false error.

---

## 1. Project rules — these are not negotiable

### Storage migration safety
- Never change a Hive box name.
- Records are stored as `Box<Map>` plain JSON. No Hive type adapters.
- `Transaction.fromJson`'s type-absent fallback is the entire migration story
  for existing user data: a record with no `type` key is an **expense**. Do not
  change it.
- Adding an *optional* key to `toJson`/`fromJson` is safe. Changing a box name, a
  stored value's type, or that default is not.
- `Location.icon` and `Location.color` already existed in the model and were
  already persisted. Do not "add" them.

### Identity
- The phone-visible app name is exactly `TBRN`. Do not rename any Dart file or
  class. The Android package stays `flutter_application_1`.
  - `android/app/src/main/AndroidManifest.xml` → `android:label="TBRN"`
  - `lib/main.dart` → `MaterialApp.title: 'TBRN'`

### Design language — already approved, do not redesign
Warm "carafe and cream" palette, exact colours: cream `#F0E1CA`, khaki
`#A8907D`, jet `#2B2722`, carafe `#4B392F`. The launcher icon uses only those
three.

Use the tokens in `lib/theme/app_theme.dart` — `AppSpacing`, `AppRadii`,
`AppColors`, `AppMotion`, `AppSurface` with `AppSurfaceTier.flat/raised/accent`.
No raw magic numbers, no hardcoded colours in screens. Nav order is fixed:
**Pack, Journey, Transactions, Places, Settings**.

`test/app_icon_test.dart` and `test/design_system_test.dart` enforce all of this.

### Category colours
`design_system_test.dart` asserts a perceptual distance of at least 150 between
every pair across `expenseCategories()` **and** `suggestedExpenseTypes()`.
It caught a real collision (Gifts vs Phone & Internet at 139). If you add a
category colour, run that test and fix the *colour* — never the threshold.

---

## 2. Done and committed — do not redo

| Commit | What |
|---|---|
| `7733b8e` | **F: adding a place is a screen, not a dialog.** New `lib/screens/locations/add_location_screen.dart` (was an `AlertDialog`). Paste-a-Google-Maps-link parsing in `lib/models/place_link.dart`. 28-icon picker (`PlaceIcons`). Fixed: `addLocation`/`updateLocation` swallow write failures into `error` and return normally, so the old dialog closed anyway and reported success on a failed save. Fixed: editing a place no longer re-files it into the active journey. Moved the "open Settings" escape hatch to `lib/utils/location_settings.dart` — a screen cannot reach a private top-level function in the file that imports it without a circular import, and this is the **only** route to background location. |
| `6788f2a` | **The Other screen duplicated rows and claimed you made them.** Two bugs. (a) `primary = _showMore ? namedTypes : namedTypes.take(4)` meant expanding rendered the list's last four rows a *second* time under the toggle. (b) "Your categories" showed the nine built-ins with the custom sparkle icon, because the screen merged a `suggestedNames` list the provider filled with those same nine built-in names. Dead plumbing deleted (`suggestedNames`, `TransactionProvider.categorySuggestions`). The screen now offers 12 suggested types that are deliberately **not** new `ExpenseCategory` values — they file as `ExpenseCategory.other` + `customName`, so storage is untouched. See `CategoryRegistry.suggestedExpenseTypes()`. |
| `e219c0d` | **How each transaction was paid — cash or online.** `PaymentMethod { cash, online }`. Nullable on purpose: every pre-existing record has no value, and defaulting to cash would put a fact in the user's data they never entered. Multiple wallets deliberately **not** built (user's explicit instruction). Also hardened `fromJson` to `(json['amount'] as num).toDouble()`. |
| `c794ac9` | **One button to create a checklist, and a demo button that fits.** The empty Pack tab showed `EmptyState`'s "Create Checklist" *and* a "New Checklist" FAB; the FAB is now hidden while the list is empty. "Add/Clear demo data" were side-by-side `Expanded` buttons and wrapped at 360dp; they stack below 380dp (`_sideBySideWidth`). |
| `b8bb8a9` | **Pack for a trip as a list.** "What are you taking? (comma separated)" → `_PackingListEditor`, a real add/remove list (commas still split on add, case-insensitive dedupe). Also fixed a **pre-existing** bug found on the way: the Journeys month navigator overflowed by 29px at 360dp (two 48dp `IconButton`s flanking a month name). The Journeys screen had never been rendered at 360dp in any test, which is why it survived — `test/journey_items_test.dart` covers it now. |
| `f4cb447` | **Light mode got a real surface ladder.** The cause was not the palette: the `ColorScheme` container roles were never set, so `surfaceContainerLow`…`surfaceContainerHigh` *all* resolved to `#f8f1e5`, the page colour. Those roles are what `Card`, `ListTile`, menus, dialogs, bottom sheets, filled text fields, chips and snack bars paint themselves with — so there was no elevation anywhere and every card was invisible against the background. New warm ladder in `AppColors`, raised cards moved off literal `Colors.white`. Dark had the identical defect and got the same treatment, extending its two existing tones. |

Last verified gate: `flutter analyze` clean, **238 tests passing**, debug APK
built.

---

## 3. In flight — uncommitted, NOT green

Three modified files, also copied to `backup/` and captured as
`backup/uncommitted-charts.patch`:

- `lib/widgets/spend_trend_cards.dart`
- `lib/screens/transactions/transactions_screen.dart`
- `analysis_options.yaml` (excludes `backup/**`)

This is the "enhance the graphs" work. **`flutter analyze` is clean but the full
test suite hangs** — see section 0. Do not build on it until that is resolved.

What changed:
- `DailyTotalsChart`: horizontal gridlines, a `peak Rs X` caption so the bars
  have something to be read against, and a `highlightedDate` param — the
  filtered-to day is drawn wider and darker, wired from `provider.selectedDay`.
- `CumulativeBalanceChart`: a dashed **zero line** via `extraLinesData`, plus
  first/last date labels. It previously had `titlesData: show: false`, i.e. no x
  axis at all.
- New `WeeklyTotalsChart` (+ `WeekTotal`, `groupByWeek`): Monday-start weeks,
  plotting a **daily average** per week so a part-week is not read as a collapse
  in spending, with a heaviest/quietest-week sentence. Rendered by
  `transactions_screen.dart` after `CumulativeBalanceChart`.
- Gridlines are drawn by testing fixed fractions of the axis
  (`_isAtFractions`) rather than by setting `FlGridData.horizontalInterval`.
  The interval approach hung the spend screen test. If you reintroduce an
  interval, expect the hang back.

---

## 4. Still to do — only after section 0 is green

1. **Flavour for the Pack, Journey and Places tabs.** The user's words: "still
   feels bland in pack, journey, places tabs … keep the UI design flow and make
   it look flavour full". They like the design language — enrich within it, do
   not redesign it. The intended direction is the backpack metaphor (what the
   app is carrying), a smart daily summary, and generally less flat screens.
2. **G: Pack reminders.** The duplicate-primary-action half is done (`c794ac9`).
   Reminders remain — `lib/services/notification_service.dart` exists; wire
   checklist/journey reminders through it.
3. **Missing features** (audited: zero files exist for any of these):
   - Search + filters: search transactions; filter by category, income/expense,
     date; sort by amount/date. `TransactionFilter` and a sort already exist in
     the provider — build on them.
   - Budgets: monthly and/or per-category limits, progress bars, "you're close
     to your food budget" style messaging.
   - Goals: "Save for headphones", emergency fund, trip — with progress.
   - Backup/restore: JSON export + import. CSV export already exists in
     `lib/services/csv_export.dart`. Note `Transaction.fromJson` now tolerates
     integer amounts, which is what a hand-edited JSON file will contain.
   - Recurring transactions: subscriptions, allowance/salary, regular bills.
   - **Skip entirely: multiple wallets/accounts** (user's explicit instruction).
4. **Final gate and report.** Format, analyze, full test, debug APK build. Then
   report under `IMPLEMENTED / VERIFIED / NOT VERIFIED / REMAINING ISSUES`.

**The device was never connected this session, so nothing has been visually
confirmed on a phone.** Say so plainly — do not claim visual verification.

---

## 5. Environment gotchas (each one cost real time)

- **Hive writes inside a `testWidgets` body deadlock.** A write started in the
  fake-async zone never completes and holds the box lock. Drive storage through
  `tester.runAsync(() async { ... })`. Consequence: you **cannot** tap a save
  button in a widget test — cover the save at the provider layer instead and say
  so in a comment.
- `await (tester.runAsync(f))!` is wrong — the `!` binds to the Future, not the
  awaited value. Use `(await tester.runAsync(f))!`.
- `runAsync` is reentrant-hostile: always await it before calling it again.
- `SemanticsFlag` is undefined; `Tristate` lives in `dart:ui`, not the flutter
  package — `import 'dart:ui' show Tristate;`. `hasFlag` is deprecated; use
  `.flagsCollection.isSelected == Tristate.isTrue`. Better: give widgets a
  `ValueKey` and use `find.byKey` — `find.bySemanticsLabel` does not resolve
  inside a bottom sheet.
- `TextFormField` is **not** a `TextField` subclass; `tester.widget<TextField>()`
  on a `TextFormField` throws a `TypeError`. Cast to `TextFormField`.
- `find.widgetWithText` matches once per `Text` descendant, so a field showing
  both its value and its floating label matches twice. Read
  `.controller!.text` instead.
- A lazy `ListView` disposes rows scrolled past. A test that only scrolls
  downwards can never find a disposed row again and will report a **false
  pass** — use a deliberately tall viewport instead.
- `JourneyProvider.initialize()` starts a 1-minute periodic timer; a widget test
  fails on a pending timer. Call `addTearDown(provider.dispose)`.
- **Long commands get killed in this environment.** Run `flutter analyze` and
  `flutter test` as separate short commands with a tight `timeout`, and redirect
  output to a file rather than piping it. Piping a full `flutter test` run to
  `tail` produced megabytes of carriage-return progress lines and got the
  session killed. Preferred:
  ```bash
  timeout 150 flutter test --reporter=failures-only > /tmp/full.log 2>&1; echo "exit=$?"; tail -20 /tmp/full.log
  ```
  `exit=124` is a hang. A clean run exits 0.
- `flutter test --reporter=compact` rewrites the same line with `\r` and is the
  worst option for a long run — it generated ~400KB of output and killed the
  session twice.

---

## 6. User expectations

One user, one phone, real personal data. They want this to be a daily-use app,
not a demo. Never run a destructive wipe or "remove all data" action against a
connected device. Commit after each verified change, and write a plain-language
log of what changed at the end.
