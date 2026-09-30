import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/services/location_insight_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

import 'other_category_screen.dart';

import 'package:flutter_application_1/utils/format.dart';

class AddExpenseSheet extends StatefulWidget {
  const AddExpenseSheet({super.key, this.existing, this.initialJourneyId});

  final Expense? existing;
  final String? initialJourneyId;

  static Future<void> show(
    BuildContext context, {
    Expense? existing,
    String? initialJourneyId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddExpenseSheet(
        existing: existing,
        initialJourneyId: initialJourneyId,
      ),
    );
  }

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late ExpenseCategory _category;
  String? _customCategoryName;
  late DateTime _date;
  String? _locationId;
  String? _journeyId;
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
    _category = existing?.category ?? ExpenseCategory.food;
    if (existing == null) {
      final recentMeta = context
          .read<TransactionProvider>()
          .recentCategories
          .firstOrNull;
      if (recentMeta != null) {
        _category = recentMeta.id.startsWith('custom:')
            ? ExpenseCategory.other
            : ExpenseCategory.values.firstWhere(
                (c) => c.name == recentMeta.id,
                orElse: () => ExpenseCategory.food,
              );
        if (recentMeta.id.startsWith('custom:')) {
          _customCategoryName = recentMeta.name;
        }
      }
    }
    _customCategoryName = existing?.customCategoryName;
    _date = existing?.date ?? DateTime.now();
    _locationId = existing?.locationId;
    _journeyId =
        existing?.journeyId ??
        widget.initialJourneyId ??
        context.read<JourneyProvider>().activeJourney?.id;
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
    final transactions = context.watch<TransactionProvider>();
    final locations = context.watch<LocationProvider>().locations;
    final journeys = context.watch<JourneyProvider>().journeys;

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
                _isEditing ? 'Edit expense' : 'Add expense',
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
              _CategoryPicker(
                selected: _category,
                customName: _customCategoryName,
                recent: transactions.recentCategories,
                popular: transactions.popularCategories,
                customCategories: transactions.recentCustomCategories,
                onSelected: (category, customName) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _category = category;
                    _customCategoryName = customName;
                  });
                },
                // "Other" is a door, not a value. It opens a screen that asks
                // what kind of other, because the answer is either a named type
                // or a name the user invents — and neither fits in a dropdown
                // wedged under the chips.
                onOther: () => _pickOtherCategory(transactions),
              ),
              if (_category == ExpenseCategory.other &&
                  _customCategoryName != null) ...[
                const SizedBox(height: AppSpacing.xs),
                _SelectedCategoryRow(
                  label: _customCategoryName!,
                  onEdit: () => _pickOtherCategory(transactions),
                ),
              ],
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
                  if (journeys.isNotEmpty)
                    _ContextMenuChip<String?>(
                      icon: Icons.route_rounded,
                      label: _journeyId == null
                          ? 'No journey'
                          : journeys
                                    .where((j) => j.id == _journeyId)
                                    .firstOrNull
                                    ?.title ??
                                'No journey',
                      value: _journeyId,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('No journey'),
                        ),
                        ...journeys.map(
                          (j) => DropdownMenuItem(
                            value: j.id,
                            child: Text(j.title),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _journeyId = v),
                    ),
                  if (locations.isNotEmpty)
                    _ContextMenuChip<String?>(
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
                  label: Text(_isEditing ? 'Save changes' : 'Save expense'),
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
        ? CategoryRegistry.metaFor(
            _category,
            customName: _customCategoryName,
          ).name
        : _descriptionController.text.trim();

    // See IncomeEditSheet._save: the write reports whether it reached storage,
    // and a failed save must keep the sheet open rather than discard what the
    // user typed.
    if (_isEditing) {
      final saved = await provider.updateTransaction(
        widget.existing!.copyWith(
          amount: double.parse(_amountController.text),
          category: _category,
          description: description,
          customCategoryName: _category == ExpenseCategory.other
              ? (_customCategoryName ?? 'Other')
              : null,
          locationId: _locationId,
          journeyId: _journeyId,
          date: _date,
          clearLocation: _locationId == null,
          clearJourney: _journeyId == null,
        ),
      );
      if (!mounted) return;
      if (!saved) {
        setState(() {
          _saving = false;
          _saveError = provider.error ?? 'Could not save. Please try again.';
        });
        return;
      }
      Navigator.pop(context);
      return;
    }

    final position = await _tryCapturePosition();

    String? locationId = _locationId;
    if (position != null && locationId == null && mounted) {
      final suggestion = LocationInsightService.suggestCheckpoint(
        context.read<LocationProvider>().locations,
        position.latitude,
        position.longitude,
      );
      if (suggestion != null) {
        final accepted = await _confirmCheckpoint(suggestion);
        if (accepted == true) {
          locationId = suggestion.id;
        } else if (accepted == false) {
          await LocationInsightService.declineCheckpoint(suggestion.id);
        }
      }
    }

    final saved = await provider.addTransaction(
      Expense(
        amount: double.parse(_amountController.text),
        category: _category,
        description: description,
        locationId: locationId,
        customCategoryName: _category == ExpenseCategory.other
            ? (_customCategoryName ?? 'Other')
            : null,
        journeyId: _journeyId,
        latitude: position?.latitude,
        longitude: position?.longitude,
        locationCapturedAt: position != null ? DateTime.now() : null,
        date: _date,
      ),
    );
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _saving = false;
        _saveError = provider.error ?? 'Could not save. Please try again.';
      });
      return;
    }
    Navigator.pop(context);
  }

  /// Opens the "Other" screen and folds the answer back into the form.
  Future<void> _pickOtherCategory(TransactionProvider transactions) async {
    final choice = await OtherCategoryScreen.show(
      context,
      currentCustomName: _customCategoryName,
      savedCustomNames: transactions.recentCustomCategories,
    );
    if (choice == null || !mounted) return;

    // Persist a newly invented name so it is offered next time. The screen only
    // collects the choice; saving it belongs here, where the form that needs it
    // already lives.
    final customName = choice.customName;
    if (customName != null) {
      await transactions.addCustomCategory(customName);
      if (!mounted) return;
    }

    setState(() {
      if (choice.category == ExpenseCategory.other) {
        // Still "other", but now with a real name attached.
        _category = ExpenseCategory.other;
        _customCategoryName = customName;
      } else {
        // They picked a named type after all, so the expense is that category
        // and the custom name is no longer relevant.
        _category = choice.category;
        _customCategoryName = null;
      }
    });
  }

  Future<Position?> _tryCapturePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      ).timeout(const Duration(seconds: 10), onTimeout: () => throw 'timeout');
    } catch (_) {
      return null;
    }
  }

  Future<bool?> _confirmCheckpoint(Location checkpoint) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.place_rounded),
        title: Text('At ${checkpoint.name}?'),
        content: const Text(
          'Link this expense to this saved place? This helps location insights.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not this time'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes'),
          ),
        ],
      ),
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

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.selected,
    required this.customName,
    required this.recent,
    required this.popular,
    required this.customCategories,
    required this.onSelected,
    required this.onOther,
  });

  /// Opens the "Other" screen. "Other" is not a value you can select and move
  /// on from; it is a question about what kind.
  final VoidCallback onOther;

  /// True once the user has given the Other bucket a real name, so the bare
  /// "Other" row stops being a door and becomes an ordinary selected category.
  bool get selectedCustomNamed =>
      selected == ExpenseCategory.other &&
      customName != null &&
      customName!.isNotEmpty;

  final ExpenseCategory selected;
  final String? customName;
  final List<CategoryMeta> recent;
  final List<CategoryMeta> popular;
  final List<String> customCategories;
  final void Function(ExpenseCategory category, String? customName) onSelected;

  /// `recent`/`popular` come straight from the provider, which counts expense
  /// and income together, so they can contain an income category such as
  /// `salary`. This picker only understands expense categories — an id it does
  /// not recognise used to be mapped through `orElse: ExpenseCategory.other`,
  /// so tapping "Salary" silently selected "Other". Drop them instead.
  static bool _isExpenseMeta(CategoryMeta meta) {
    if (meta.id.startsWith('custom:')) return true;
    return ExpenseCategory.values.any((c) => c.name == meta.id);
  }

  static ExpenseCategory? _categoryFor(CategoryMeta meta) {
    if (meta.id.startsWith('custom:')) return ExpenseCategory.other;
    for (final c in ExpenseCategory.values) {
      if (c.name == meta.id) return c;
    }
    return null;
  }

  bool _isSelected(CategoryMeta meta) {
    if (meta.id.startsWith('custom:')) {
      return selected == ExpenseCategory.other &&
          customName != null &&
          meta.id == 'custom:${customName!.toLowerCase()}';
    }
    return selected == ExpenseCategory.other
        ? meta.id == 'other' && customName == null
        : meta.id == selected.name;
  }

  @override
  Widget build(BuildContext context) {
    final recentMetas = recent.where(_isExpenseMeta).take(4).toList();
    final popularMetas = popular
        .where((m) => _isExpenseMeta(m))
        .where((m) => !recentMetas.any((r) => r.id == m.id))
        .take(4)
        .toList();
    final allMetas =
        ExpenseCategory.values.map((c) => CategoryRegistry.metaFor(c)).toList()
          ..sort((a, b) => a.popularity.compareTo(b.popularity));

    Widget section(String label, List<CategoryMeta> metas) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CategorySectionLabel(label),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: metas.map((meta) {
              final isTheOtherBucket =
                  meta.id == 'other' && !selectedCustomNamed;
              return _CategoryTile(
                meta: meta,
                selected: _isSelected(meta),
                // The bare "Other" entry opens the screen. A saved custom name
                // is a value in its own right and selects directly, the same as
                // any other row.
                onTap: isTheOtherBucket
                    ? onOther
                    : () => onSelected(
                        _categoryFor(meta) ?? ExpenseCategory.other,
                        meta.id.startsWith('custom:')
                            ? meta.id.substring('custom:'.length)
                            : null,
                      ),
                showsChevron: isTheOtherBucket,
              );
            }).toList(),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recentMetas.isNotEmpty) ...[
          section('Recent', recentMetas),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (popularMetas.isNotEmpty) ...[
          section('Popular', popularMetas),
          const SizedBox(height: AppSpacing.sm),
        ],
        section('All', [
          ...allMetas,
          ...customCategories.map(
            (n) =>
                CategoryRegistry.metaFor(ExpenseCategory.other, customName: n),
          ),
        ]),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.meta,
    required this.selected,
    required this.onTap,
    this.showsChevron = false,
  });

  final CategoryMeta meta;
  final bool selected;
  final VoidCallback onTap;

  /// Marks a row that navigates somewhere rather than selecting a value, so it
  /// does not look like the other tiles.
  final bool showsChevron;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Category ${meta.name}',
      child: InkWell(
        borderRadius: AppRadii.smallRadius,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? meta.color.withValues(alpha: 0.18) : null,
            borderRadius: AppRadii.smallRadius,
            border: Border.all(
              color: selected ? meta.color : colorScheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                meta.icon,
                size: 18,
                color: selected ? meta.color : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                meta.name,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? meta.color : colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              // Signals that this row goes somewhere rather than picking a
              // value in place.
              if (showsChevron) ...[
                const SizedBox(width: AppSpacing.xxs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the name the user gave the Other bucket, with a way back into the
/// screen that collects it.
class _SelectedCategoryRow extends StatelessWidget {
  const _SelectedCategoryRow({required this.label, required this.onEdit});

  final String label;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppSurface(
      tier: AppSurfaceTier.flat,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(Icons.payments_rounded, size: 18, color: colorScheme.primary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Filed under "$label"',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('Change')),
        ],
      ),
    );
  }
}

class _ContextMenuChip<T> extends StatelessWidget {
  const _ContextMenuChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  /// Widest a context chip is allowed to become.
  ///
  /// [DropdownMenu] sizes itself to its longest entry, so a long journey or
  /// place title made the chip claim the whole width available inside the
  /// sheet (measured at 312dp on a 360dp phone) and pushed its siblings onto
  /// their own lines. The chip caps itself instead.
  static const double maxChipWidth = 220;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxChipWidth),
      child: DropdownMenu<T>(
        initialSelection: value,
        onSelected: (v) => onChanged(v as T),
        dropdownMenuEntries: items
            .map(
              (item) => DropdownMenuEntry<T>(
                value: item.value as T,
                label: (item.child as Text).data ?? '',
              ),
            )
            .toList(),
        // Without a cap the selected value is drawn at its natural width,
        // which is what let the menu claim the whole row.
        maxLines: 1,
        inputDecorationTheme: const InputDecorationTheme(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 0,
          ),
        ),
        leadingIcon: Icon(icon, size: 18),
        hintText: label,
        textStyle: Theme.of(context).textTheme.labelLarge,
        menuStyle: MenuStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadii.smallRadius),
          ),
          // The open menu gets the same cap, so a long entry scrolls inside a
          // popup rather than producing a popup wider than the screen.
          maximumSize: WidgetStatePropertyAll(
            const Size(maxChipWidth, double.infinity),
          ),
        ),
      ),
    );
  }
}
