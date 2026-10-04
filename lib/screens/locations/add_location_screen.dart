import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/location_settings.dart';

/// Add or edit a saved place.
///
/// A full screen rather than the dialog it replaced. The old form was five
/// stacked fields in an AlertDialog with a "Use current location" button wedged
/// between them, which meant the coordinates — the only two fields that are
/// genuinely awkward to type — were as prominent as the name, and entering a
/// place meant scrolling inside a dialog.
///
/// The order is now: say what it is, say where it is (paste a link, use where
/// you are, or type it), then the details.
class AddLocationScreen extends StatefulWidget {
  const AddLocationScreen({
    super.key,
    this.location,
    this.initialLatitude,
    this.initialLongitude,
  });

  /// Null to add a new place.
  final Location? location;

  /// A position to open the form WITH, without editing anything.
  ///
  /// This is what makes "save the spot you keep spending at" possible. The
  /// coordinates are known — the app has them on four transactions already — so
  /// asking for them again is busywork, and the only thing the user actually has
  /// to supply is the name.
  ///
  /// SEPARATE FROM [location] ON PURPOSE. Pre-filling by passing a whole `Location`
  /// would flip the screen into edit mode, change the title to "Edit place", and
  /// route the save to `updateLocation` — so offering to save a new spot would
  /// overwrite whatever place happened to be constructed. Two parameters, two
  /// intents.
  final double? initialLatitude;
  final double? initialLongitude;

  static Future<bool?> show(
    BuildContext context, {
    Location? location,
    double? initialLatitude,
    double? initialLongitude,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddLocationScreen(
          location: location,
          initialLatitude: initialLatitude,
          initialLongitude: initialLongitude,
        ),
      ),
    );
  }

  @override
  State<AddLocationScreen> createState() => _AddLocationScreenState();
}

class _AddLocationScreenState extends State<AddLocationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  late final TextEditingController _description;
  late final TextEditingController _link;
  final _radius = TextEditingController();

  late String _iconKey;
  String? _journeyId;
  bool _locating = false;
  String? _linkProblem;

  bool get _isEditing => widget.location != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.location;
    final seededLat = existing?.latitude ?? widget.initialLatitude;
    final seededLng = existing?.longitude ?? widget.initialLongitude;
    _name = TextEditingController(text: existing?.name ?? '');
    _latitude = TextEditingController(
      text: seededLat == null ? '' : seededLat.toStringAsFixed(6),
    );
    _longitude = TextEditingController(
      text: seededLng == null ? '' : seededLng.toStringAsFixed(6),
    );
    _description = TextEditingController(text: existing?.description ?? '');
    _link = TextEditingController();
    _radius.text = (existing?.radiusMeters ?? Location.defaultRadiusMeters)
        .toStringAsFixed(0);
    _iconKey = existing?.icon ?? PlaceIcons.defaultKey;
    _journeyId = existing?.journeyId;
  }

  @override
  void dispose() {
    _name.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _description.dispose();
    _link.dispose();
    _radius.dispose();
    super.dispose();
  }

  /// Fills the coordinates from a pasted link.
  void _applyLink() {
    final parsed = PlaceLinkParser.parse(_link.text);
    if (parsed == null) {
      setState(() {
        _linkProblem = PlaceLinkParser.looksLikeALink(_link.text)
            ? 'That link has no coordinates in it.'
            : 'That does not look like a maps link.';
      });
      return;
    }
    setState(() {
      _linkProblem = null;
      _latitude.text = parsed.latitude.toStringAsFixed(6);
      _longitude.text = parsed.longitude.toStringAsFixed(6);
      // A link usually carries the place name, so take it rather than making
      // the user retype what they just pasted.
      final name = parsed.name;
      if (name != null && name.isNotEmpty && _name.text.trim().isEmpty) {
        _name.text = name;
      }
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _linkProblem = null;
    });
    final provider = context.read<LocationProvider>();
    await provider.updateCurrentPosition();
    if (!mounted) return;
    final position = provider.currentPosition;
    setState(() => _locating = false);

    if (position == null) {
      // When the only way forward is a permission the app cannot request again
      // (the user chose "don't ask again", or the phone's location toggle is
      // off), a bare error gives the user no next step. Background location
      // can only ever be granted here, so this is the one route to it.
      if (provider.needsSystemSettings) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.error ?? 'Could not get a location fix.'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettingsForLocation(context),
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Could not get a location fix.'),
        ),
      );
      return;
    }
    setState(() {
      _latitude.text = position.latitude.toStringAsFixed(6);
      _longitude.text = position.longitude.toStringAsFixed(6);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<LocationProvider>();
    final journeys = context.read<JourneyProvider>();

    final location = Location(
      id: widget.location?.id,
      name: _name.text.trim(),
      latitude: double.parse(_latitude.text.trim()),
      longitude: double.parse(_longitude.text.trim()),
      description: _description.text.trim(),
      radiusMeters:
          double.tryParse(_radius.text.trim()) ?? Location.defaultRadiusMeters,
      // Editing preserves the trip exactly as it was; a new place joins the
      // active trip by default. Falling back to the active trip while editing
      // would silently re-file a place the user had deliberately left unfiled.
      journeyId: _isEditing
          ? _journeyId
          : (_journeyId ?? journeys.activeJourney?.id),
      icon: _iconKey,
    );

    if (_isEditing) {
      await provider.updateLocation(location);
    } else {
      await provider.addLocation(location);
    }
    if (!mounted) return;

    // Both mutators record a failed write in `error` and return normally, so
    // popping without this check would close the screen and claim success for
    // a place that was never stored.
    if (provider.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(provider.error!)));
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final journeys = context.watch<JourneyProvider>().journeys;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit place' : 'Add a place')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.screenPadding,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Phewa Lake',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Give it a name' : null,
            ),
            const SizedBox(height: AppSpacing.md),

            // The two awkward fields, so every way of avoiding typing them is
            // right here rather than scattered.
            Text(
              'Where is it?',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Paste a Google Maps link',
                hintText: 'https://maps.app.goo.gl/…',
                errorText: _linkProblem,
                suffixIcon: IconButton(
                  tooltip: 'Use the coordinates from this link',
                  icon: const Icon(Icons.link_rounded),
                  onPressed: _applyLink,
                ),
              ),
              onSubmitted: (_) => _applyLink(),
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton.icon(
              onPressed: _locating ? null : _useCurrentLocation,
              icon: _locating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('Use where I am now'),
            ),
            const SizedBox(height: AppSpacing.md),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latitude,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Latitude'),
                    validator: (v) {
                      final parsed = double.tryParse((v ?? '').trim());
                      if (parsed == null) return 'Needed';
                      if (parsed < -90 || parsed > 90) return '−90 to 90';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: _longitude,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Longitude'),
                    validator: (v) {
                      final parsed = double.tryParse((v ?? '').trim());
                      if (parsed == null) return 'Needed';
                      if (parsed < -180 || parsed > 180) return '−180 to 180';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              'Icon',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // A grid rather than a dropdown: the whole point is to see the
            // options, and a menu of 28 icons hides all but one at a time.
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 7,
              mainAxisSpacing: AppSpacing.xs,
              crossAxisSpacing: AppSpacing.xs,
              children: [
                for (final key in PlaceIcons.keys)
                  _IconChoice(
                    iconKey: key,
                    selected: key == _iconKey,
                    onTap: () => setState(() => _iconKey = key),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            TextFormField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Gate is on the north side',
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            TextFormField(
              controller: _radius,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Checkpoint radius',
                suffixText: 'm',
                helperText:
                    'How close you must be for this place to count. '
                    'Up to ${Location.maxRadiusMeters.toStringAsFixed(0)} m.',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                final parsed = double.tryParse((v ?? '').trim());
                if (parsed == null || parsed <= 0) return 'Enter a distance';
                // REFUSED, not silently clamped. The constructor already clamps,
                // so a 900 m radius would otherwise save as 200 and the field
                // would read 900 until the screen reopened — the user would be
                // told their value was accepted and it was not.
                if (parsed > Location.maxRadiusMeters) {
                  return 'Use ${Location.maxRadiusMeters.toStringAsFixed(0)} m or less';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),

            if (journeys.isNotEmpty) ...[
              DropdownButtonFormField<String?>(
                initialValue: _journeyId,
                decoration: const InputDecoration(labelText: 'Trip'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Not part of a trip'),
                  ),
                  for (final j in journeys)
                    DropdownMenuItem<String?>(
                      value: j.id,
                      child: Text(
                        j.destination.isEmpty ? 'Trip' : j.destination,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _journeyId = v),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            FilledButton.icon(
              onPressed: _save,
              icon: Icon(_isEditing ? Icons.check_rounded : Icons.add_rounded),
              label: Text(_isEditing ? 'Save changes' : 'Add place'),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.iconKey,
    required this.selected,
    required this.onTap,
  });

  /// The stored icon key.
  ///
  /// Named `iconKey` and not `key`: a `String` field called `key` is an
  /// invalid override of `Widget.key`, which is a `Key?`.
  final String iconKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = PlaceIcons.resolve(iconKey);

    return Semantics(
      // A stable identity for this cell, so selection state can be read back
      // rather than inferred from pixel colours.
      key: ValueKey('place-icon-$iconKey'),
      button: true,
      selected: selected,
      label: iconKey,
      child: InkWell(
        borderRadius: AppRadii.smallRadius,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            borderRadius: AppRadii.smallRadius,
            border: Border.all(
              color: selected ? colorScheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
