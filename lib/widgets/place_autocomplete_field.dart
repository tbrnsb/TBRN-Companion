import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/theme/app_theme.dart';

/// A text field that suggests the places you have already saved.
///
/// Typing filters the saved locations; tapping one fills the field. The
/// "use my location" button fills the field with your current saved place.
///
/// The suggestions ride in an [Overlay] rather than in the layout below the
/// field, so opening them never pushes the rest of the form down — on the
/// journey sheet, a panel that reflowed the packing list under it would be
/// worse than no suggestions at all.
class PlaceAutocompleteField extends StatefulWidget {
  const PlaceAutocompleteField({
    super.key,
    required this.controller,
    required this.label,
    required this.onUseCurrentLocation,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onUseCurrentLocation;

  @override
  State<PlaceAutocompleteField> createState() => _PlaceAutocompleteFieldState();
}

class _PlaceAutocompleteFieldState extends State<PlaceAutocompleteField> {
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  List<String> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _showOverlay() {
    // Never stack: a refocus without an intervening blur would otherwise
    // insert a SECOND entry that nothing ever removes.
    _removeOverlay();

    _overlayEntry = OverlayEntry(
      // The field's REAL geometry, read on every rebuild rather than once at
      // focus. A fixed 200 was narrower than the field on every phone in the
      // test matrix; capturing the size when the overlay opened fixed that
      // but then froze it, so a rotation or keyboard resize left the panel
      // hanging off the side of a field that had since changed shape.
      builder: (context) {
        final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
        final size = box?.size;
        return Positioned(
          width: size?.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            // Just under the field's own bottom edge, plus the standard gap —
            // measured from the same box as the width, so it tracks the real
            // field height instead of a hardcoded 50.
            offset: Offset(0, (size?.height ?? 56) + 4),
            child: Material(
              elevation: 4,
              borderRadius: AppRadii.smallRadius,
              clipBehavior: Clip.antiAlias,
              child: _suggestions.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          dense: true,
                          title: Text(suggestion),
                          onTap: () {
                            widget.controller.text = suggestion;
                            // Close the panel and the keyboard: the field has
                            // its answer.
                            _focusNode.unfocus();
                          },
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _updateSuggestions(String query) {
    final trimmed = query.trim();
    setState(() {
      if (trimmed.isEmpty) {
        // An empty field suggests NOTHING. `contains('')` is true for every
        // string, so the old filter put every saved place on screen the
        // moment the field came into focus.
        _suggestions = const [];
      } else {
        final needle = trimmed.toLowerCase();
        _suggestions = context
            .read<LocationProvider>()
            .locations
            .where((location) => location.name.toLowerCase().contains(needle))
            .map((location) => location.name)
            .toList();
      }
    });
    // The panel is a SEPARATE element subtree from this field: setState
    // rebuilds the field, not the entry, so the entry has to be told its
    // builder should run again.
    _overlayEntry?.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        key: _fieldKey,
        controller: widget.controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: IconButton(
            tooltip: 'Use my current location',
            icon: const Icon(Icons.my_location_rounded),
            onPressed: widget.onUseCurrentLocation,
          ),
        ),
        onChanged: _updateSuggestions,
      ),
    );
  }
}
