/// The dates a user is allowed to pick, in one place.
///
/// These bounds exist because the pickers were each doing their own arithmetic,
/// and each of them was wrong in its own way: a trip can start in the future, an
/// expense cannot, and a transaction is scoped to the month on screen. Three
/// inline `DateTime(now.year - 2, ...)` expressions in three files is three
/// places for the next change to be made in two of them.
///
/// One home for them also means month NAVIGATION can share the floor. That is
/// the point of putting them here: the month chevrons stop at the earliest month
/// a picker would accept, so a user cannot page back to a month they then cannot
/// record anything in.
///
/// Nothing here reads the clock at import time. Every method takes `now`, so a
/// test can ask about a fixed date and the answer does not change at midnight.
library;

/// How far back the app's pickers reach, in YEARS.
///
/// Two years, not "since 2020" and not "the beginning of time". A picker that
/// opens on 1980 makes the user scroll through decades to reach last month, and
/// one that opens today makes history unrecordable. Two years covers a full
/// annual cycle of a trip, a tax return and a warranty, which is what people
/// actually backfill.
class AppDateWindow {
  AppDateWindow._();

  /// How far back the app reaches.
  static const int yearsBack = 2;

  /// How far forward a TRIP may start.
  ///
  /// A trip is a plan, so it has a future: booking something for next spring is
  /// ordinary, and refusing it would make the app useless for its main purpose.
  static const int yearsForwardForTrips = 1;

  /// The first month a user may page back to: [yearsBack] years ago, floored to
  /// the first of that month.
  static DateTime monthFloor(DateTime now) =>
      DateTime(now.year - yearsBack, now.month, 1);

  /// The last month a user may page to: the current one.
  ///
  /// A month cannot be spent in before it arrives, so this is the wall clock,
  /// not [now] itself. Paging forward past it lands on an empty month with a
  /// total of zero, which reads as "you spent nothing" rather than as "it has not
  /// happened yet" — and an expense recorded there is a real expense dated in
  /// the future, which is a bug that surfaces much later in an export.
  static DateTime monthCeiling(DateTime now) =>
      DateTime(now.year, now.month, 1);

  /// The first day a trip may start.
  static DateTime tripFirst(DateTime now) => DateTime(now.year - yearsBack);

  /// The last day a trip may start, inclusive.
  static DateTime tripLast(DateTime now) =>
      DateTime(now.year + yearsForwardForTrips, now.month + 1, 0);

  /// The first day an expense or income may be dated.
  static DateTime recordFirst(DateTime now) => DateTime(now.year - yearsBack);

  /// The last day an expense or income may be dated, inclusive: today.
  ///
  /// Not `now.add(a day)`: a spend is something that happened, and yesterday's
  /// late entry is ordinary while tomorrow's is a different mistake.
  static DateTime recordLast(DateTime now) =>
      DateTime(now.year, now.month, now.day);

  /// Whether [month] is within the navigable range, month-first.
  static bool isNavigable(DateTime month, DateTime now) {
    final m = DateTime(month.year, month.month);
    return !m.isBefore(monthFloor(now)) && !m.isAfter(monthCeiling(now));
  }

  /// [month] moved by [delta] months, clamped to the navigable range.
  ///
  /// Clamping rather than refusing, so a chevron that is somehow pressed at a
  /// boundary leaves the user where they were instead of throwing. The chevrons
  /// are disabled there too; this is the belt to that braces.
  static DateTime clampMonth(DateTime month, DateTime now) {
    final floor = monthFloor(now);
    final ceiling = monthCeiling(now);
    if (month.isBefore(floor)) return floor;
    if (month.isAfter(ceiling)) return ceiling;
    return DateTime(month.year, month.month);
  }
}
