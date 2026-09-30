import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/services/trip_snapshot.dart';

/// Writing and sharing a trip snapshot as a file.
///
/// Follows `csv_export.dart` exactly: share_plus can only hand a recipient a
/// FILE, so the JSON is written to disk first and the path is what gets shared.
/// [writeSnapshot] is separated from [shareSnapshot] for the same reason — the
/// part worth testing is the file that lands on disk, and that can be asserted
/// without a platform channel.
class TripSnapshotExport {
  TripSnapshotExport._();

  /// A filesystem-safe name for [journey], e.g. `tbrn-trip-pokhara-4k2j8q.json`.
  ///
  /// The code is in the name because two phones produce two files for the same
  /// trip and the chat they arrive through is usually full of other files.
  static String fileNameFor(Journey journey) {
    final slug = _slug(journey.title.isEmpty ? 'trip' : journey.title);
    final code = journey.tripCode;
    return 'tbrn-trip-$slug${code == null ? '' : '-${code.toLowerCase()}'}.json';
  }

  /// Writes [snapshot] to a temporary file and returns it.
  ///
  /// The system temp directory, which on Android is the app cache dir — no
  /// storage permission, no new dependency.
  static Future<File> writeSnapshot(
    TripSnapshot snapshot,
    Journey journey,
  ) async {
    final dir = await Directory.systemTemp.createTemp('tbrn_trip_export');
    final file = File('${dir.path}/${fileNameFor(journey)}');
    await file.writeAsString(snapshot.encode());
    return file;
  }

  /// Writes and hands [snapshot] to the platform share sheet.
  ///
  /// Returns [TripSnapshotShareResult] rather than the `File`: the caller only
  /// needs to report what happened, and returning a `dart:io` type would force
  /// every caller to import it.
  static Future<TripSnapshotShareResult> shareSnapshot(
    TripSnapshot snapshot,
  ) async {
    final file = await writeSnapshot(snapshot, snapshot.journey);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'TBRN trip — ${snapshot.journey.title}',
        text:
            'Trip costs from ${snapshot.exportedBy}. Import it in TBRN and tell '
            'it which one you are.',
      ),
    );
    return TripSnapshotShareResult(
      shared: true,
      fileName: fileNameFor(snapshot.journey),
    );
  }
}

class TripSnapshotShareResult {
  const TripSnapshotShareResult({required this.shared, required this.fileName});

  final bool shared;
  final String fileName;
}

/// Lowercase, dash-separated, safe to put in a filename.
///
/// Anything that is not a letter or a digit becomes a dash, so a title with a
/// slash or a colon in it cannot produce a path that escapes the directory.
String _slug(String value) {
  final cleaned = value
      .toLowerCase()
      .split('')
      .map(
        (c) =>
            (c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122) ||
                (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57)
            ? c
            : '-',
      )
      .join()
      .replaceAll(RegExp('-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return cleaned.isEmpty ? 'trip' : cleaned;
}
