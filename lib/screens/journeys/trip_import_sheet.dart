import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/services/trip_snapshot.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';

/// Reading someone else's trip file, in two required steps.
///
/// PREVIEW FIRST, ALWAYS. This reads a financial record that somebody else
/// wrote — and a file can be anything, from a trip two years ago to the wrong
/// person entirely. Applying it with no preview could duplicate a trip, merge
/// into the wrong one, or pull in hundreds of records the user never agreed to.
/// So the file is parsed and described in full before a single write.
///
/// THEN: WHICH ONE ARE YOU? Not optional, not last. Without it the app can
/// compute the whole settlement but cannot tell the importing user what *they*
/// owe — which is the entire reason they opened the file. And the file cannot
/// answer it: Raj's copy records Raj as "me", so Sita importing it must not end
/// up as Raj.
class TripImportSheet extends StatefulWidget {
  const TripImportSheet({super.key, required this.journeyId});

  final String journeyId;

  static Future<bool?> show(BuildContext context, {required String journeyId}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TripImportSheet(journeyId: journeyId),
    );
  }

  /// Runs the whole flow from a file the user already has.
  ///
  /// Returns true when something was applied.
  static Future<bool> showForFile(BuildContext context, File file) async {
    final messenger = ScaffoldMessenger.of(context);
    String contents;
    try {
      contents = await file.readAsString();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not read that file: $e')),
      );
      return false;
    }

    final parsed = TripSnapshot.decode(contents);
    if (!parsed.isValid) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(parsed.message ?? 'That file could not be read.'),
        ),
      );
      return false;
    }

    if (!context.mounted) return false;
    final journeyId = await showTripImportPreview(context, parsed.snapshot!);
    return journeyId != null;
  }

  @override
  State<TripImportSheet> createState() => _TripImportSheetState();
}

/// The preview, as a function so it can be reached from a file the user picked
/// without a sheet of its own in the way.
Future<String?> showTripImportPreview(
  BuildContext context,
  TripSnapshot snapshot,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ImportPreviewSheet(snapshot: snapshot),
  );
}

class _TripImportSheetState extends State<TripImportSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final messenger = ScaffoldMessenger.of(context);
    // No file picker dependency, deliberately. Adding one is a new permission on
    // a permission-light app for a feature reached once or twice a trip. The
    // path is typed instead, and the OS share sheet is the way a file actually
    // arrives here in normal use.
    final path = _controller.text.trim();
    if (path.isEmpty) return;

    final file = File(path);
    if (!file.existsSync()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No file at that path.')),
      );
      return;
    }
    if (!context.mounted) return;
    Navigator.pop(context);
    await TripImportSheet.showForFile(context, file);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Import a trip file',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Ask a friend to tap Share on their trip summary, then paste the '
              'path to the file they sent you.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('import-file-path'),
              controller: _controller,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: '/storage/emulated/0/Download/tbrn-trip-….json',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('import-file-continue'),
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Read that file'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step one: what is in this file, and who sent it. Nothing is written yet.
class _ImportPreviewSheet extends StatefulWidget {
  const _ImportPreviewSheet({required this.snapshot});

  final TripSnapshot snapshot;

  @override
  State<_ImportPreviewSheet> createState() => _ImportPreviewSheetState();
}

class _ImportPreviewSheetState extends State<_ImportPreviewSheet> {
  /// Which participant is the user. Null until they pick, because there is no
  /// safe default: guessing would put a confident wrong number on screen.
  String? _localParticipantId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencySymbol = context.select<SettingsProvider, String>(
      (s) => s.currency.symbol,
    );
    final snapshot = widget.snapshot;
    final journey = snapshot.journey;
    final participants = journey.participants;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Check before importing', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'This is somebody else\'s record of a trip. Nothing has been '
              'added yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            AppSurface(
              tier: AppSurfaceTier.raised,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PreviewRow(
                    label: 'Trip',
                    value: journey.title.isEmpty
                        ? 'Untitled trip'
                        : journey.title,
                  ),
                  _PreviewRow(label: 'Sent by', value: snapshot.exportedBy),
                  _PreviewRow(label: 'People', value: '${participants.length}'),
                  _PreviewRow(
                    label: 'Expenses',
                    value: '${snapshot.expenses.length}',
                  ),
                  _PreviewRow(
                    label: 'Total',
                    value: AppFormat.money(
                      snapshot.total,
                      symbol: currencySymbol,
                    ),
                  ),
                ],
              ),
            ),

            if (participants.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text('Which one are you?', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'The file records who paid, not who is reading it. Pick '
                'yourself and the app will tell you what you owe.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final participant in participants)
                    ChoiceChip(
                      key: ValueKey('import-who-${participant.id}'),
                      label: Text(participant.name),
                      selected: participant.id == _localParticipantId,
                      onSelected: (_) =>
                          setState(() => _localParticipantId = participant.id),
                    ),
                ],
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            AppSurface(
              tier: AppSurfaceTier.flat,
              color: theme.colorScheme.secondaryContainer,
              child: Text(
                'Importing only adds. Anything you already have, or anything '
                'you deleted from this trip, stays as it is.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('import-confirm'),
                    onPressed: _localParticipantId == null
                        ? null
                        : () => _apply(context),
                    child: const Text('Import'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _apply(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final journeys = context.read<JourneyProvider>();
    final snapshot = widget.snapshot;

    final result = await journeys.importSnapshot(snapshot);

    // Who-am-I is asked for per phone, never read from the file: Raj's copy
    // saying "Raj" must not turn Sita into Raj.
    await journeys.setLocalParticipant(result.journeyId, _localParticipantId);

    if (!context.mounted) return;
    Navigator.pop(context, result.journeyId);
    messenger.showSnackBar(SnackBar(content: Text(result.describe())));
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
