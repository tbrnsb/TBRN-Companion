import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:daily_companion/providers/location_provider.dart';

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
  OverlayEntry? _overlayEntry;
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _overlayEntry?.remove();
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
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 200,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, 50),
          child: Material(
            elevation: 4.0,
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: _suggestions
                  .map(
                    (suggestion) => ListTile(
                      title: Text(suggestion),
                      onTap: () {
                        widget.controller.text = suggestion;
                        _removeOverlay();
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _updateSuggestions(String query) {
    final locations = context.read<LocationProvider>().locations;
    setState(() {
      _suggestions = locations
          .where(
            (location) =>
                location.name.toLowerCase().contains(query.toLowerCase()),
          )
          .map((location) => location.name)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Column(
        children: [
          TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            decoration: InputDecoration(
              labelText: widget.label,
              suffixIcon: IconButton(
                icon: const Icon(Icons.my_location),
                onPressed: widget.onUseCurrentLocation,
              ),
            ),
            onChanged: _updateSuggestions,
          ),
        ],
      ),
    );
  }
}
