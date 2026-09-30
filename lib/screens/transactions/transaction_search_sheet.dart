import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

/// The part of search that is not the text field: an amount range and a category
/// multi-select.
///
/// Opens as a sheet rather than inline, because three controls plus nine
/// category chips is more than a screen's worth of space above the fold, and
/// pushing the results down to make room would hide the thing being searched.
///
/// Returns the edited query, or null if the user cancelled — which is distinct
/// from "no change", so a cancel is genuinely a cancel and does not silently
/// apply a half-finished edit the way a dismissed day sheet used to.
class TransactionSearchSheet extends StatefulWidget {
  const TransactionSearchSheet({super.key, required this.initial});

  final TransactionSearchQuery initial;

  /// Shows the sheet and resolves to the new query, or null on cancel.
  static Future<TransactionSearchQuery?> show(
    BuildContext context,
    TransactionSearchQuery initial,
  ) {
    return showModalBottomSheet<TransactionSearchQuery>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TransactionSearchSheet(initial: initial),
    );
  }

  @override
  State<TransactionSearchSheet> createState() => _TransactionSearchSheetState();
}

class _TransactionSearchSheetState extends State<TransactionSearchSheet> {
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  late Set<String> _categories;

  @override
  void initState() {
    super.initState();
    _minController = TextEditingController(
      text: widget.initial.minAmount?.toStringAsFixed(0) ?? '',
    );
    _maxController = TextEditingController(
      text: widget.initial.maxAmount?.toStringAsFixed(0) ?? '',
    );
    _categories = {...widget.initial.categories};
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  /// The typed minimum, or null when the field is blank or not a number.
  ///
  /// A half-typed or unparseable bound is treated as "no bound" rather than
  /// silently becoming 0, which would otherwise exclude every row the moment
  /// the user cleared the field to retype it.
  double? get _min => double.tryParse(_minController.text.trim());
  double? get _max => double.tryParse(_maxController.text.trim());

  bool get _isInverted => _min != null && _max != null && _min! > _max!;

  void _apply() {
    if (_isInverted) return;
    Navigator.pop(
      context,
      widget.initial.copyWith(
        minAmount: _min,
        maxAmount: _max,
        clearMin: _min == null,
        clearMax: _max == null,
        categories: _categories,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final options = searchCategoryOptions();

    return SafeArea(
      child: Padding(
        // Lifts the sheet above the keyboard, so the category chips stay
        // reachable while the amount fields are being typed into.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Filter results',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (_categories.isNotEmpty ||
                        _minController.text.isNotEmpty ||
                        _maxController.text.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          _minController.clear();
                          _maxController.clear();
                          setState(() => _categories.clear());
                        },
                        child: const Text('Reset'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Amount', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('search-min-amount'),
                        controller: _minController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Min',
                          hintText: '0',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('search-max-amount'),
                        controller: _maxController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Max',
                          hintText: 'Any',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                // A range with its ends the wrong way round matches nothing, and
                // with no explanation it reads as the search being broken. Say it
                // on the control rather than returning a silent empty result.
                if (_isInverted)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'Min is above max — that range matches nothing.',
                      key: const ValueKey('search-range-warning'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Text('Categories', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final option in options)
                      FilterChip(
                        key: ValueKey('search-cat-${option.id}'),
                        label: Text(option.label),
                        selected: _categories.contains(option.id),
                        onSelected: (on) {
                          setState(() {
                            if (on) {
                              _categories.add(option.id);
                            } else {
                              _categories.remove(option.id);
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('search-apply-filters'),
                        onPressed: _isInverted ? null : _apply,
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
