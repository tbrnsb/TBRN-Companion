import 'dart:io';

import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter_application_1/providers/transaction_provider.dart';

/// Sharing this month's transactions as a CSV file.
///
/// The CSV itself comes from [TransactionProvider.exportCurrentMonthCsv], which
/// until now had no callers. share_plus can only hand a recipient a file, so
/// the text is written to disk first; [writeCsv] is separated from [share] so
/// the part worth testing — the file that lands on disk — can be asserted
/// without a platform channel.
class CsvExport {
  CsvExport._();

  /// File name for [month], e.g. `transactions-2026-09.csv`.
  static String fileNameFor(DateTime month) =>
      'transactions-${DateFormat('yyyy-MM').format(month)}.csv';

  /// Writes [csv] to a temporary file and returns it.
  ///
  /// Uses the system temp directory, which on Android is the app cache dir, so
  /// no storage permission and no new dependency are needed.
  static Future<File> writeCsv(String csv, DateTime month) async {
    final dir = await Directory.systemTemp.createTemp('daily_companion_export');
    final file = File('${dir.path}/${fileNameFor(month)}');
    await file.writeAsString(csv);
    return file;
  }

  /// Writes and shares [provider]'s current month.
  ///
  /// Returns `shared: false` when the month has nothing recorded, so the caller
  /// can say so rather than offering the user an empty file. The [File] type is
  /// deliberately kept out of the return value: the caller only needs to report
  /// what happened, and returning a `dart:io` type would force every caller to
  /// import it.
  static Future<CsvExportResult> shareCurrentMonth(
    TransactionProvider provider, {
    DateTime? month,
  }) async {
    final target = month ?? provider.currentMonth ?? DateTime.now();
    final csv = provider.exportCurrentMonthCsv();

    // Header only means no transactions were recorded this month.
    final dataRows = csv
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
    if (dataRows <= 1) {
      return CsvExportResult(shared: false, fileName: fileNameFor(target));
    }

    final file = await writeCsv(csv, target);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Daily Companion — ${DateFormat.yMMMM().format(target)}',
      ),
    );
    return CsvExportResult(shared: true, fileName: fileNameFor(target));
  }
}

/// Outcome of a [CsvExport.shareCurrentMonth] call.
class CsvExportResult {
  const CsvExportResult({required this.shared, required this.fileName});

  /// False when there was nothing to export.
  final bool shared;

  final String fileName;
}
