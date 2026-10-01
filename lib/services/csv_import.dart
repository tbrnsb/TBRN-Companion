import 'dart:convert';
import 'dart:io';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/services/csv_document.dart';

/// The result of reading a CSV, before anything has been written.
///
/// PREVIEW BEFORE WRITING, ALWAYS. This is the reverse of
/// [CsvExport] and it is deliberately a separate step from the write: a file can
/// be anything — a bank statement, an export from a different app, the wrong
/// person entirely — and applying hundreds of rows with no preview would leave
/// the user with data they did not agree to and would have to delete one by one.
///
/// [rows] holds EVERY row, valid or not. A rejected row is shown with its reason
/// rather than dropped, because a file that quietly loses four of its twenty
/// transactions is worse than one that refuses and says which four.
class CsvImportPlan {
  const CsvImportPlan({
    required this.rows,
    required this.duplicates,
    required this.fileName,
  });

  /// Every parsed row, in file order, each marked valid or rejected.
  final List<ParsedCsvRow> rows;

  /// Rows whose [ParsedCsvRow.dedupeKey] is already in the user's ledger.
  ///
  /// Computed against the WHOLE device, not the month on screen: the point is
  /// that importing the same file twice changes nothing, and a check scoped to
  /// the visible month would re-add a September row while the user browses
  /// October.
  final Set<String> duplicates;

  final String fileName;

  List<ParsedCsvRow> get rejected =>
      rows.where((r) => !r.isValid).toList(growable: false);

  List<ParsedCsvRow> get newRows => rows
      .where((r) => r.isValid && !duplicates.contains(r.dedupeKey))
      .toList(growable: false);

  bool get isEmpty => newRows.isEmpty;

  bool get hasContent => rows.isNotEmpty;

  /// What to tell the user about this file, in words.
  String get summary {
    if (rows.isEmpty) return 'No transactions found in $fileName.';
    final parts = <String>[
      '${newRows.length} to import',
      if (duplicates.isNotEmpty) '${duplicates.length} already here',
      if (rejected.isNotEmpty) '${rejected.length} could not be read',
    ];
    return '${parts.join(', ')}.';
  }

  /// The same file with [dropped] row keys removed.
  ///
  /// Add-only and non-destructive: dropping a row from a plan only stops it being
  /// written. Nothing already in the ledger is touched, which is the whole
  /// contract of this importer.
  CsvImportPlan without(Set<String> dropped) {
    return CsvImportPlan(
      rows: rows
          .where((r) => !dropped.contains('${r.lineNumber}'))
          .toList(growable: false),
      duplicates: duplicates,
      fileName: fileName,
    );
  }

  /// Reads [text] and works out what importing it would do.
  ///
  /// Pure: no writes, no provider. The caller passes [existing] — the ledger as
  /// read from storage, which the provider owns — so this stays testable and so
  /// the shared-trip rule is applied ONCE, upstream, rather than a second time
  /// here in a subtly different form.
  static CsvImportPlan analyse({
    required String text,
    required List<Transaction> existing,
    required String fileName,
  }) {
    final rows = CsvParser.parse(text);

    // Keys of everything already in the ledger. `existing` is expected to be
    // LIVE and MINE already — see TransactionProvider.existingLedgerForImport —
    // so a trashed row does not block a re-import, and another participant's
    // trip expense neither blocks nor leaks.
    final known = <String>{for (final t in existing) _keyOf(t)};
    final duplicates = <String>{
      for (final row in rows)
        if (row.isValid && known.contains(row.dedupeKey)) row.dedupeKey,
    };

    return CsvImportPlan(
      rows: rows,
      duplicates: duplicates,
      fileName: fileName,
    );
  }

  static String _keyOf(Transaction t) {
    final amountPaise = (t.amount * 100).round();
    final date = t.date.toIso8601String().substring(0, 10);
    return '$date|$amountPaise|${t.description.trim().toLowerCase()}';
  }

  /// Reads a picked file's text, tolerating an encoding surprise.
  ///
  /// `allowMalformed: true` because a CSV with one odd byte in it is still
  /// readable for every other row, and throwing away two hundred good
  /// transactions over one bad character would be the wrong trade.
  static Future<String> readText(File file) async {
    final bytes = await file.readAsBytes();
    return _decode(bytes);
  }

  static String _decode(List<int> bytes) {
    // A UTF-8 BOM survives as U+FEFF and would make the first column read as
    // '﻿date' — an unrecognised header, and then the first row treated as a
    // header and silently dropped. Excel writes one routinely.
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return _decodeLatin(bytes.sublist(3));
    }
    return _decodeLatin(bytes);
  }

  static String _decodeLatin(List<int> bytes) {
    try {
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    } catch (_) {
      // Never reached with allowMalformed, and the fallback exists so this
      // function cannot become the one that throws on a bad file.
      return String.fromCharCodes(bytes);
    }
  }
}
