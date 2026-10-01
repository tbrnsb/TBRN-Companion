import 'package:intl/intl.dart';

import 'package:flutter_application_1/models/index.dart';

/// THE CSV format, defined once, in one place.
///
/// Export writes it and import reads it, both through this class. That is the
/// only way a round trip can hold: two hand-written versions of a CSV format
/// drift the first time somebody adds a column, and the drift is invisible until
/// someone exports on one phone and imports on another.
///
/// **The documented format, and the only one.** `date,description,amount,category,type`
/// — fixed column order, `yyyy-MM-dd` dates, amounts as plain decimals, the
/// category as the human name the UI shows, and `type` as `Expense` or `Income`.
///
/// Deliberately NOT supported: bank-statement layouts, quoted headers with
/// different names, per-row currency symbols, and PDF. A row whose shape is not
/// this one is reported as unrecognised and skipped — never guessed at.
class CsvDocument {
  CsvDocument._();

  static const String header = 'date,description,amount,category,type';

  static const int columnCount = 5;

  /// Encodes one transaction as a CSV row.
  ///
  /// Every field is quoted, including the numeric ones. A quoted number is valid
  /// CSV and every spreadsheet reads it, and it removes the whole class of bug
  /// where a description containing a comma silently shifts every later column.
  static String encodeRow(Transaction t, {String currencySymbol = ''}) {
    final amount = t.amount.toStringAsFixed(2);
    return [
      _quote(DateFormat('yyyy-MM-dd').format(t.date)),
      _quote(t.description),
      _quote(amount),
      _quote(t.effectiveCategoryName),
      _quote(t.type.toString().split('.').last),
    ].join(',');
  }

  static String _quote(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  /// Splits CSV text into rows, honouring quotes.
  ///
  /// A hand-rolled split on `,` is the classic wrong answer: `"Lunch, with
  /// Raj"` becomes two columns and every field after it shifts, which the parser
  /// then reports as a corrupt amount rather than as the quoting mistake it is.
  static List<List<String>> parse(String text) {
    final rows = <List<String>>[];
    var field = StringBuffer();
    var row = <String>[];
    var inQuotes = false;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];

      if (inQuotes) {
        if (char == '"') {
          // A doubled quote inside a quoted field is a literal quote.
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(char);
        }
        continue;
      }

      switch (char) {
        case '"':
          inQuotes = true;
        case ',':
          row.add(field.toString());
          field = StringBuffer();
        case '\n':
          row.add(field.toString());
          field = StringBuffer();
          rows.add(row);
          row = <String>[];
        case '\r':
          // Swallowed. A CRLF file would otherwise leave a stray \r on the last
          // field of every row, and "food\r" is not a category the registry has.
          break;
        default:
          field.write(char);
      }
    }

    // Whatever is left is the last row. A file with no trailing newline is
    // normal, and dropping its final row would silently lose a record.
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }

    return rows.where((r) => r.any((cell) => cell.trim().isNotEmpty)).toList();
  }
}

/// A parsed row, or the reason it could not be.
class ParsedCsvRow {
  const ParsedCsvRow._({
    required this.lineNumber,
    required this.date,
    required this.description,
    required this.amount,
    required this.categoryName,
    required this.isExpense,
    this.failure,
    this.raw,
  });

  /// A row that parsed cleanly.
  factory ParsedCsvRow.valid({
    required int lineNumber,
    required DateTime date,
    required String description,
    required double amount,
    required String categoryName,
    required bool isExpense,
  }) {
    return ParsedCsvRow._(
      lineNumber: lineNumber,
      date: date,
      description: description,
      amount: amount,
      categoryName: categoryName,
      isExpense: isExpense,
    );
  }

  /// A row that could not be read, with the reason. Shown in the preview, never
  /// swallowed: a file that silently loses four of its twenty rows is worse than
  /// one that refuses and says why.
  factory ParsedCsvRow.rejected({
    required int lineNumber,
    required String reason,
    required String raw,
  }) {
    return ParsedCsvRow._(
      lineNumber: lineNumber,
      date: null,
      description: null,
      amount: null,
      categoryName: null,
      isExpense: null,
      failure: reason,
      raw: raw,
    );
  }

  final int lineNumber;
  final DateTime? date;
  final String? description;
  final double? amount;
  final String? categoryName;
  final bool? isExpense;

  /// Null when the row parsed.
  final String? failure;

  /// The original line, so the preview can show what was actually rejected.
  final String? raw;

  bool get isValid => failure == null;

  /// This row as a transaction, or null when it was rejected.
  ///
  /// The category goes through [CategoryRegistry.metaFor], so a custom or
  /// suggested name keeps its own metadata and an unknown one falls back to
  /// `other` — the same path the add sheet takes. Never a new enum value: a
  /// transaction stores its category by name, so importing one would not
  /// invalidate a single stored record.
  Transaction? toTransaction() {
    if (!isValid) return null;
    if (isExpense!) {
      final meta = _resolveCategory(categoryName!);
      return Expense(
        amount: amount!,
        category: meta.isCustomName ? ExpenseCategory.other : meta.enumValue,
        customCategoryName: meta.isCustomName ? meta.displayName : null,
        description: description!.trim().isEmpty ? 'Imported' : description!,
        date: date,
      );
    }
    return Income(
      amount: amount!,
      category: categoryName!.trim().isEmpty ? 'other' : categoryName!.trim(),
      description: description!.trim().isEmpty ? 'Imported' : description!,
      date: date,
    );
  }

  /// The stable identity of a row, used for duplicate detection.
  ///
  /// Date + amount + description, deliberately WITHOUT the id. The point is that
  /// the same file imported twice changes nothing, and a fresh `id` is generated
  /// on every import — so including it would make every row new every time and
  /// the check would never fire. The trip-share importer makes the same argument
  /// for `TripImporter`.
  ///
  /// Description case-folded, because "Groceries" and "groceries" are the same
  /// purchase recorded twice, and a case-sensitive hash would let both through.
  String get dedupeKey {
    final amountPaise = (amount! * 100).round();
    return '${date!.toIso8601String().substring(0, 10)}|$amountPaise|'
        '${description!.trim().toLowerCase()}';
  }

  static _ResolvedCategory _resolveCategory(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const _ResolvedCategory(
        ExpenseCategory.other,
        'Other',
        isCustomName: false,
      );
    }
    for (final category in ExpenseCategory.values) {
      if (CategoryRegistry.metaFor(category).name.toLowerCase() ==
          trimmed.toLowerCase()) {
        return _ResolvedCategory(category, trimmed, isCustomName: false);
      }
    }
    return _ResolvedCategory(
      ExpenseCategory.other,
      trimmed,
      isCustomName: true,
    );
  }
}

class _ResolvedCategory {
  const _ResolvedCategory(
    this.enumValue,
    this.displayName, {
    required this.isCustomName,
  });

  final ExpenseCategory enumValue;
  final String displayName;
  final bool isCustomName;
}

/// Parses whole CSV text into rows.
///
/// Separate from [CsvDocument] because parsing needs a line number and a reason,
/// and those are per-file concerns rather than per-format ones.
class CsvParser {
  const CsvParser._();

  static List<ParsedCsvRow> parse(String text) {
    final rows = CsvDocument.parse(text);
    if (rows.isEmpty) return const [];

    // The first row is the header when it looks like one. Not assumed: a file
    // with no header is a plausible thing to be handed, and dropping its first
    // transaction because it happened to start with the word "date" would be a
    // silent data loss.
    final hasHeader = _looksLikeHeader(rows.first);

    final result = <ParsedCsvRow>[];
    for (var i = 0; i < rows.length; i++) {
      if (i == 0 && hasHeader) continue;
      final lineNumber = i + 1;
      final cells = rows[i];

      if (cells.length < CsvDocument.columnCount) {
        result.add(
          ParsedCsvRow.rejected(
            lineNumber: lineNumber,
            reason:
                'expected ${CsvDocument.columnCount} columns, found ${cells.length}',
            raw: cells.join(','),
          ),
        );
        continue;
      }

      final date = _parseDate(cells[0].trim());
      if (date == null) {
        result.add(
          ParsedCsvRow.rejected(
            lineNumber: lineNumber,
            reason: 'unreadable date',
            raw: cells.join(','),
          ),
        );
        continue;
      }

      // Type tolerance on the amount, deliberately matching what
      // `Transaction.fromJson` already does. A hand-edited or machine-written
      // file very often carries an integer, and `(json['amount'] as num)` proves
      // the app already accepts one. A strict `double.parse` would reject a
      // perfectly good `250` that this app's own storage reads without complaint.
      final amount = _parseAmount(cells[2].trim());
      if (amount == null) {
        result.add(
          ParsedCsvRow.rejected(
            lineNumber: lineNumber,
            reason: 'unreadable amount',
            raw: cells.join(','),
          ),
        );
        continue;
      }

      // The raw value is kept for the error message and the lowercased one is
      // matched. Reporting the lowercased form would print "unknown type
      // \"transfer\"" when the file said "Transfer", which sends the user looking
      // for a spelling mistake that is not there.
      final typeRaw = cells[4].trim();
      final isExpense = switch (typeRaw.toLowerCase()) {
        'expense' || 'expenses' || '' => true,
        'income' => false,
        _ => null,
      };
      if (isExpense == null) {
        result.add(
          ParsedCsvRow.rejected(
            lineNumber: lineNumber,
            reason: 'unknown type "$typeRaw"',
            raw: cells.join(','),
          ),
        );
        continue;
      }

      result.add(
        ParsedCsvRow.valid(
          lineNumber: lineNumber,
          date: date,
          description: cells[1],
          amount: amount,
          categoryName: cells[3],
          isExpense: isExpense,
        ),
      );
    }
    return result;
  }

  static bool _looksLikeHeader(List<String> first) {
    if (first.isEmpty) return false;
    final first0 = first[0].trim().toLowerCase();
    // Comparing only the first column, because the exporter writes
    // `"date","description",...` and a strict five-way comparison would stop
    // matching the moment quoting changed.
    return first0 == 'date' || first0 == 'transaction date';
  }

  /// Reads a date written as `yyyy-MM-dd`.
  ///
  /// Returns midnight local, which is what the exporter wrote and what every
  /// date in the app is stored as. An unparseable date is null rather than a
  /// throw: a bad date is a bad ROW, and one bad row must not abandon the file.
  static DateTime? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  /// Reads an amount.
  ///
  /// Tolerates an integer, which is what a spreadsheet produces for a whole
  /// number and what `Transaction.fromJson` already tolerates in JSON. Rejects a
  /// currency symbol, which no exporter here ever writes and which would be
  /// ambiguous about the decimal separator anyway.
  static double? _parseAmount(String raw) {
    if (raw.isEmpty) return null;
    final cleaned = raw.replaceAll(',', '').trim();
    final parsed = double.tryParse(cleaned);
    if (parsed == null || !parsed.isFinite) return null;
    if (parsed < 0) return null;
    return parsed;
  }
}
