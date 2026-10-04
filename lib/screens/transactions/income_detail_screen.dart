import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/services/transaction_location_service.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/format.dart';
import 'package:daily_companion/widgets/context_menu_chip.dart';
import 'package:daily_companion/widgets/transaction_location_block.dart';

import '../locations/add_location_screen.dart';

class IncomeDetailScreen extends StatelessWidget {
  const IncomeDetailScreen({super.key, required this.income});

  final Income income;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final current =
        context
            .watch<TransactionProvider>()
            .transactions
            .where((t) => t.id == income.id)
            .whereType<Income>()
            .firstOrNull ??
        income;

    final meta = current.categoryMeta;

    return Scaffold(
      appBar: AppBar(
        title: Text(meta.name),
        actions: [
          IconButton(
            tooltip: 'Edit income',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () =>
                IncomeEditSheet.show(context: context, existing: current),
          ),
          IconButton(
            tooltip: 'Delete income',
            icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
            onPressed: () => _confirmDelete(context, current),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.12),
              borderRadius: AppRadii.mediumRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: meta.color.withValues(alpha: 0.2),
                        borderRadius: AppRadii.smallRadius,
                      ),
                      child: Icon(meta.icon, color: meta.color),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        current.description.isEmpty
                            ? meta.name
                            : current.description,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  AppFormat.signedMoney(
                    current.amount,
                    isExpense: false,
                    symbol: context.select<SettingsProvider, String>(
                      (s) => s.currency.symbol,
                    ),
                  ),
                  style: textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppFormat.relativeDay(current.date),
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          TransactionDetailRow(
            icon: meta.icon,
            iconColor: meta.color,
            label: 'Category',
            value: current.effectiveCategoryName,
          ),
          const SizedBox(height: AppSpacing.lg),

          // The SAME block the expense detail screen uses, so a payment gets the
          // place, the journey, the capture time, the coordinates and the Maps
          // action — identical to what an expense gets. This row set was absent
          // here entirely, which is the gap: income recorded no location, so it
          // had nothing to show and nowhere to link to.
          TransactionLocationBlock(transaction: current),
          const SizedBox(height: AppSpacing.lg),

          OutlinedButton.icon(
            onPressed: () =>
                IncomeEditSheet.show(context: context, existing: current),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Edit income'),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: () => _confirmDelete(context, current),
            icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
            label: Text(
              'Delete income',
              style: TextStyle(color: colorScheme.error),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colorScheme.error.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Income income) {
    final provider = context.read<TransactionProvider>();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete income?'),
        content: Text('Remove "${income.description}" from your records?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await provider.deleteTransaction(income.id);
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class IncomeEditSheet extends StatefulWidget {
  const IncomeEditSheet({super.key, this.existing});

  final Income? existing;

  static Future<void> show({required BuildContext context, Income? existing}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => IncomeEditSheet(existing: existing),
    );
  }

  @override
  State<IncomeEditSheet> createState() => _IncomeEditSheetState();
}

class _IncomeEditSheetState extends State<IncomeEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late String _category;
  late DateTime _date;

  /// Which saved place this income belongs to, if the user named one.
  ///
  /// Null is the normal state and means "no place chosen", NOT "no place" — the
  /// raw coordinates are captured regardless, and stay null here until either
  /// the user picks from the chip or agrees to a proximity prompt.
  String? _locationId;
  bool _saving = false;
  String? _saveError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amountController = TextEditingController(
      text: existing == null ? '' : existing.amount.toStringAsFixed(0),
    );
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _category = existing?.category ?? 'salary';
    _date = existing?.date ?? DateTime.now();
    _locationId = existing?.locationId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Watched, so a place saved elsewhere while this sheet is open appears in
    // the menu without the sheet having to be reopened.
    final locations = context.watch<LocationProvider>().locations;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isEditing ? 'Edit income' : 'Add income',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              TextFormField(
                controller: _amountController,
                autofocus: !_isEditing,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  prefixText: context.select<SettingsProvider, String>(
                    (s) => s.currency.symbol,
                  ),
                  prefixStyle: textTheme.headlineSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  hintText: '0',
                  hintStyle: textTheme.headlineMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),

              _CategorySectionLabel('Category'),
              const SizedBox(height: AppSpacing.xs),
              _IncomeCategoryPicker(
                selected: _category,
                onSelected: (category) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _category = category;
                  });
                },
              ),

              const SizedBox(height: AppSpacing.md),

              TextFormField(
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Description (optional)',
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.today_rounded, size: 18),
                    label: Text(AppFormat.relativeDay(_date).split(',').first),
                    onPressed: _pickDate,
                  ),
                  // The place chip, the SAME control the expense form uses.
                  //
                  // Income had no way to say where money arrived, so a place the
                  // user was paid at — an office, a client, a home — was
                  // invisible to everything that reads a location. Sharing the
                  // control rather than writing a second one is what stops the
                  // two forms drifting apart again.
                  if (locations.isNotEmpty)
                    ContextMenuChip<String?>(
                      icon: Icons.place_rounded,
                      label: _locationId == null
                          ? 'No place'
                          : locations
                                    .where((l) => l.id == _locationId)
                                    .firstOrNull
                                    ?.name ??
                                'No place',
                      value: _locationId,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('No place'),
                        ),
                        ...locations.map(
                          (l) => DropdownMenuItem(
                            value: l.id,
                            child: Text(l.name),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _locationId = v),
                    ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              if (_saveError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: AppRadii.smallRadius,
                  ),
                  child: Text(
                    _saveError!,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _isEditing ? Icons.check_rounded : Icons.add_rounded,
                        ),
                  label: Text(_isEditing ? 'Save changes' : 'Save income'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });

    final provider = context.read<TransactionProvider>();
    final description = _descriptionController.text.trim().isEmpty
        ? CategoryRegistry.metaForIncome(_category).name
        : _descriptionController.text.trim();

    // addTransaction/updateTransaction report whether the write reached
    // storage. Ignoring that and popping regardless is what used to lose a
    // failed save: the sheet closed, the typed amount was gone, and the only
    // trace was an error on the screen underneath the sheet.
    final bool saved;
    if (_isEditing) {
      saved = await provider.updateTransaction(
        widget.existing!.copyWith(
          amount: double.parse(_amountController.text),
          category: _category,
          description: description,
          locationId: _locationId,
          clearLocation: _locationId == null,
          date: _date,
        ),
      );
    } else {
      // THE SAME FOUR RULES AS AN EXPENSE, in the same order, because they are
      // the same question: capture the position, ask about a nearby saved place,
      // save the coordinates either way, then offer to name the spot if it keeps
      // coming up. Money arriving somewhere is recorded in the same place, by the
      // same phone, at the same moment as money leaving it.
      final position = await TransactionLocationService.capturePosition();

      String? locationId = _locationId;
      if (position != null && locationId == null && mounted) {
        final linked = await TransactionLocationService.confirmProximity(
          context,
          locations: context.read<LocationProvider>().locations,
          latitude: position.latitude,
          longitude: position.longitude,
          noun: 'payment',
        );
        if (linked != null) locationId = linked.id;
      }

      saved = await provider.addTransaction(
        Income(
          amount: double.parse(_amountController.text),
          category: _category,
          description: description,
          locationId: locationId,
          latitude: position?.latitude,
          longitude: position?.longitude,
          locationCapturedAt: position != null ? DateTime.now() : null,
          date: _date,
        ),
      );

      if (saved && mounted) {
        await _maybeOfferToSaveSpot(provider, position);
      }
    }

    if (!mounted) return;

    if (!saved) {
      // Keep the sheet open with the entered values intact so the user can
      // retry, instead of leaving a spinner that never stops.
      setState(() {
        _saving = false;
        _saveError = provider.error ?? 'Could not save. Please try again.';
      });
      return;
    }

    Navigator.pop(context);
  }

  /// Offers to name the spot, once the same spot has come up often enough.
  ///
  /// The income twin of the expense sheet's method, calling the same two shared
  /// functions. Written twice on purpose — once per sheet — rather than pulled
  /// into a base class the two do not otherwise share, because the alternative
  /// is a third copy of the capture rules by the time anything else needs them.
  Future<void> _maybeOfferToSaveSpot(
    TransactionProvider provider,
    Position? position,
  ) async {
    if (position == null || !mounted) return;

    final candidate = TransactionLocationService.clusterAfterSave(
      transactions: provider.allLiveTransactions(),
      savedLocations: context.read<LocationProvider>().locations,
    );
    if (candidate == null) return;

    final wantsSave = await offerToSaveCluster(
      context,
      candidate,
      noun: 'Payments',
    );
    if (!wantsSave || !mounted) return;

    await AddLocationScreen.show(
      context,
      initialLatitude: candidate.centerLatitude,
      initialLongitude: candidate.centerLongitude,
    );
  }
}

class _CategorySectionLabel extends StatelessWidget {
  const _CategorySectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _IncomeCategoryPicker extends StatelessWidget {
  const _IncomeCategoryPicker({
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The six built-in income categories, plus any the user has named as income
    // in Settings. A custom income category is a first-class option on the form,
    // not a footnote: the bug was that this picker only walked
    // `IncomeCategory.values` and so never saw the registry a custom category is
    // loaded into -- a category filed under income was invisible here, even
    // though it was stored correctly.
    final categories = [
      for (final category in IncomeCategory.values) category.meta,
      ...CategoryRegistry.customCategories
          .where((c) => c.kind == CategoryKind.income)
          .map(CategoryRegistry.metaForCustom),
    ];

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: categories.map((meta) {
        final isSelected = meta.id == selected;

        return ChoiceChip(
          label: Text(meta.name),
          selected: isSelected,
          onSelected: (_) => onSelected(meta.id),
          selectedColor: meta.color.withValues(alpha: 0.15),
          labelStyle: TextStyle(
            color: isSelected ? meta.color : colorScheme.onSurfaceVariant,
          ),
          side: BorderSide(
            color: isSelected ? meta.color : colorScheme.outline,
          ),
          avatar: Icon(
            meta.icon,
            size: 18,
            color: isSelected ? meta.color : colorScheme.onSurfaceVariant,
          ),
        );
      }).toList(),
    );
  }
}
