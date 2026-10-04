import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:daily_companion/models/index.dart';

import 'location_insight_service.dart';

/// Where a transaction happened, and what to do about it.
///
/// ONE implementation for BOTH directions, because the two are the same question.
/// Location capture used to live inside the expense sheet as a private method,
/// which is why income had none: money arriving somewhere is recorded in exactly
/// the same place, by exactly the same phone, at exactly the same moment as money
/// leaving it, and a rule that only one of them follows is a rule that will drift.
///
/// The rules this service applies, in the order they are applied to a save:
///   1. Capture a position, if one is obtainable without asking.
///   2. Ask "Are you at [place]?" if the fix is inside a saved place's radius.
///   3. Save the coordinates either way, linked or not.
///   4. Offer to name the spot once the same spot has come up often enough.
class TransactionLocationService {
  TransactionLocationService._();

  /// How long to wait for a fix before giving up and saving anyway.
  ///
  /// Bounded on purpose. An unbounded read would leave the Save button spinning
  /// on a cold GPS in a basement, and a transaction the user asked to record is
  /// worth more than the coordinates on it.
  static const Duration _fixTimeout = Duration(seconds: 8);

  /// The wall-clock bound on top of the plugin's own.
  static const Duration _hardTimeout = Duration(seconds: 10);

  /// A position for this transaction, if one is obtainable WITHOUT ASKING.
  ///
  /// It never prompts, and that is a hard rule rather than a preference. Saving
  /// used to call [Geolocator.requestPermission] here, so every transaction a user
  /// saved could be met with a system location dialog — arriving at the moment
  /// they pressed Save, interrupting the one action they had already decided on,
  /// for a feature they had not asked for.
  ///
  /// ACCEPTS `whileInUse`, which is the fix. This used to require `always`, and
  /// `always` is not what Android grants: the normal permission flow gives
  /// "Allow while using the app", and "Allow all the time" needs a second,
  /// separate request screen that the app never showed. So the gate was
  /// unsatisfiable in practice and the capture silently returned null for almost
  /// every real user — which is why expenses had no coordinates on them and the
  /// feature looked broken rather than absent.
  ///
  /// A fix taken while the app is in the foreground needs no more than
  /// `whileInUse`, so requiring more than that was requiring permission for a
  /// capability this code path does not use.
  ///
  /// Returns null — never throws — for every failure. A transaction the user
  /// asked to record must save with or without a position.
  static Future<Position?> capturePosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      final permission = await Geolocator.checkPermission();
      const usable = {LocationPermission.whileInUse, LocationPermission.always};
      if (!usable.contains(permission)) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: _fixTimeout,
      ).timeout(_hardTimeout, onTimeout: () => throw 'timeout');
    } catch (_) {
      return null;
    }
  }

  /// "Are you at [place]?" — the saved place whose radius contains this fix.
  ///
  /// Returns the place the user confirmed, or null when there is no candidate,
  /// when the user declined, or when the sheet went away.
  ///
  /// Declining is remembered for a cooldown, so a user who is repeatedly near a
  /// place they are not at is not asked on every single transaction.
  static Future<Location?> confirmProximity(
    BuildContext context, {
    required List<Location> locations,
    required double latitude,
    required double longitude,
    required String noun,
  }) async {
    final suggestion = LocationInsightService.suggestCheckpoint(
      locations,
      latitude,
      longitude,
    );
    if (suggestion == null) return null;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.place_rounded),
        title: Text('Are you at ${suggestion.name}?'),
        content: Text(
          'This $noun was recorded inside the radius of this saved place. '
          'Link it so the two are counted together?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (accepted == true) return suggestion;
    // A "no" is an answer worth keeping. Re-asking on the very next transaction
    // at the same spot is how a helpful prompt becomes something to tap past.
    if (accepted == false) {
      await LocationInsightService.declineCheckpoint(suggestion.id);
    }
    return null;
  }

  /// The unsaved spot this transaction just made worth naming, if any.
  ///
  /// Called AFTER the transaction is written, because the cluster count includes
  /// the transaction being saved — asking on the fourth record has to be able to
  /// see all four.
  static FrequentLocationCandidate? clusterAfterSave({
    required List<Transaction> transactions,
    required List<Location> savedLocations,
  }) {
    final candidates = LocationInsightService.findFrequentLocations(
      transactions: transactions,
      savedLocations: savedLocations,
    );
    return candidates.isEmpty ? null : candidates.first;
  }
}

/// Asks whether to save a spot the user keeps transacting in.
///
/// Split out from [TransactionLocationService] so it can be reused verbatim from
/// both sheets without either of them owning the wording.
Future<bool> offerToSaveCluster(
  BuildContext context,
  FrequentLocationCandidate candidate, {
  required String noun,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final scheme = Theme.of(context).colorScheme;

  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.push_pin_rounded),
      title: const Text('You have been spending here a lot'),
      content: Text(
        '$noun has been recorded here ${candidate.transactionCount} times '
        '(${candidate.dayCount} '
        '${candidate.dayCount == 1 ? 'day' : 'days'}) near '
        '${candidate.coordinateLabel}. Save it as a place so the app can '
        'recognise it next time?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'not-now'),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, 'save'),
          child: const Text('Save place'),
        ),
      ],
    ),
  );

  if (choice == 'save') return true;
  if (choice == 'not-now' && messenger.mounted) {
    await LocationInsightService.dismissFrequentLocation(candidate.key);
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Saved coordinates kept. No place created.'),
        backgroundColor: scheme.surfaceContainerHighest,
      ),
    );
  }
  return false;
}
