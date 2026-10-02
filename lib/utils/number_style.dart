import 'package:intl/intl.dart';

/// How a number is grouped and punctuated.
///
/// NOT a locale. [intl]'s locale machinery would answer "what is right for
/// Madrid", and the question actually being asked is "which of the shapes below
/// do I want" — a person who reads `1 234 567,89` every day and is now looking at
/// an app that writes `1,234,567.89` has not been given a locale, they have been
/// given the wrong one of four shapes they recognise. A dropdown of four
/// explicit shapes is a question they can answer; a list of locales is not.
///
/// Every option here is a real convention somebody writes, which is what makes
/// the list short enough to be a dropdown rather than a search field.
enum NumberStyle {
  /// `1,234,567` and `1,234,567.89` — comma thousands, dot decimal.
  ///
  /// The default, and what the app has always written. English and the machine
  /// format everybody meets first.
  commaDot,

  /// `1,234,567` and `1,234,567.89` read as whole units; the paise come out
  /// only when there are some.
  ///
  /// Kept as its own option rather than folded into [commaDot] because "show me
  /// the decimals" and "use commas" are two separate choices, and a person who
  /// wants one does not necessarily want the other.
  commaDotNoDecimals,

  /// `1 234 567.89` — space thousands, dot decimal.
  ///
  /// The ISO 31-0 form, and what most of Europe and Scandinavia write.
  spaceDot,

  /// `1 234 567,89` — space thousands, comma decimal.
  ///
  /// German, French, Italian, Spanish, Portuguese and Dutch. The one that is
  /// most often got wrong, because the comma is a decimal point in it and an app
  /// that writes `1 234 567.89` is not merely unfamiliar, it reads as a
  /// different number to somebody who scans the separator.
  spaceComma,
}

extension NumberStyleX on NumberStyle {
  /// The pattern handed to [NumberFormat].
  ///
  /// `#,##0` is the thousands-grouped whole part in every locale intl supports,
  /// and `.` / `,` after it are the decimal separator, so the shape is fully
  /// described by these two characters. A space thousands separator is a
  /// non-breaking space (U+00A0) and NOT U+0020: an ordinary space is a word
  /// break, so a group could be split across a line and `1 234` would come out
  /// as `1` and `234` on two lines.
  String get pattern => switch (this) {
    NumberStyle.commaDot => '#,##0.##',
    NumberStyle.commaDotNoDecimals => '#,##0',
    NumberStyle.spaceDot => '#,##0.##',
    NumberStyle.spaceComma => '#,##0.##',
  };

  /// Whether the decimals are shown at all.
  bool get showsDecimals => this != NumberStyle.commaDotNoDecimals;

  /// The label in the dropdown.
  String get label => switch (this) {
    NumberStyle.commaDot => '1,234,567.89',
    NumberStyle.commaDotNoDecimals => '1,234,567',
    NumberStyle.spaceDot => '1 234 567.89',
    NumberStyle.spaceComma => '1 234 567,89',
  };

  /// What the shape is called, under the label.
  String get title => switch (this) {
    NumberStyle.commaDot => 'Commas, dot decimal',
    NumberStyle.commaDotNoDecimals => 'Whole amounts only',
    NumberStyle.spaceDot => 'Spaces, dot decimal',
    NumberStyle.spaceComma => 'Spaces, comma decimal',
  };

  /// A real example, so the dropdown shows the shape rather than describing it.
  static const String example = '1234567.89';
}

/// Applies a [NumberStyle] to a number.
///
/// [NumberFormat] is built per call rather than cached, because intl resolves a
/// pattern through the CURRENT locale and caching one would freeze whichever
/// locale happened to be in force when the cache was filled.
String formatWith(NumberStyle style, double value) {
  // A non-breaking space between groups, for the two space-separated shapes.
  // intl has no pattern character for it, so the formatted result is rewritten
  // afterwards -- which is also the only way to be sure the space is the one
  // that will not break a line.
  //
  // PINNED TO en_US, deliberately. intl resolves `,` and `.` in a pattern
  // through the CURRENT locale, so on a device set to German the pattern
  // '#,##0.##' comes back as '1.234.567,89' and the rewrite below would then turn
  // the DECIMAL comma into a group separator -- '1.234.567 89'. Pinning the
  // locale makes the four shapes mean what their labels say on every device,
  // which is the whole point of offering them as explicit choices rather than
  // deferring to the locale.
  final grouped = NumberFormat(style.pattern, 'en_US').format(value);
  return switch (style) {
    NumberStyle.commaDot || NumberStyle.commaDotNoDecimals => grouped,
    NumberStyle.spaceDot => grouped.replaceAll(',', ' '),
    NumberStyle.spaceComma => grouped.replaceAll(',', ' ').replaceAll('.', ','),
  };
}
