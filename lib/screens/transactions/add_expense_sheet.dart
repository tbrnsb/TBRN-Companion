import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/services/transaction_location_service.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/widgets/context_menu_chip.dart';

import '../locations/add_location_screen.dart';
import 'other_category_screen.dart';

import 'package:daily_companion/utils/format.dart';

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

  /// Defaults to cash for a new entry so the common Nepal case is one tap and
  /// a save. An existing record keeps whatever it was filed with, including
  /// nothing at all — an old record that predates this field is not retrofitted
  /// with a guess.
  late PaymentMethod _paymentMethod;
  late DateTime _date;
  String? _locationId;
  String? _journeyId;

  /// Which participant fronted this, on a shared trip.
  ///
  /// Null on a personal trip and on an expense saved before this field existed,
  /// which are the same thing: nobody tracked a payer. Defaults to the user's
  /// own participant so the common case — "I paid" — needs no interaction at
  /// all. It is one field inside the sheet, not a new step in the flow.
  String? _paidByParticipantId;
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
    _paymentMethod = existing?.paymentMethod ?? PaymentMethod.cash;
    _date = existing?.date ?? DateTime.now();
    _locationId = existing?.locationId;
    _journeyId =
        existing?.journeyId ??
        widget.initialJourneyId ??
        context.read<JourneyProvider>().activeJourney?.id;
    _paidByParticipantId = existing?.paidByParticipantId;
    _syncPaidByWithTrip();
  }

  /// Points the payer at the user whenever the selected trip is a shared one.
  ///
  /// Called when the trip changes and once at the start, so switching to a
  /// shared trip starts with the payer already being the user — the field is a
  /// confirmation, not an obstacle. Switching to a personal trip, or to one
  /// where this user is not on the roster, clears it, because recording a payer
  /// for a trip that is not shared would be asserting something untrue.
  void _syncPaidByWithTrip() {
    final trip = _selectedJourney;
    if (trip == null || !trip.isShared) {
      _paidByParticipantId = null;
      return;
    }
    final known = trip.participants.any((p) => p.id == _paidByParticipantId);
    if (known) return;

    _paidByParticipantId =
        trip.localParticipant?.id ?? trip.participants.first.id;
  }

  /// The journey this expense is being filed against, if it is one of the
  /// journeys this phone knows.
  Journey? get _selectedJourney {
    final id = _journeyId;
    if (id == null) return null;
    for (final journey in context.read<JourneyProvider>().journeys) {
      if (journey.id == id) return journey;
    }
    return null;
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

              _PaymentMethodPicker(
                value: _paymentMethod,
                onChanged: (method) {
                  HapticFeedback.selectionClick();
                  setState(() => _paymentMethod = method);
                },
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
                    ContextMenuChip<String?>(
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
                      onChanged: (v) => setState(() {
                        _journeyId = v;
                        _syncPaidByWithTrip();
                      }),
                    ),
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

              if (_selectedJourney?.isShared ?? false) ...[
                _PaidByPicker(
                  journey: _selectedJourney!,
                  value: _paidByParticipantId,
                  onChanged: (id) => setState(() => _paidByParticipantId = id),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

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
          paymentMethod: _paymentMethod,
          date: _date,
          clearLocation: _locationId == null,
          clearJourney: _journeyId == null,
          paidByParticipantId: _paidByParticipantId,
          clearPaidByParticipant: _paidByParticipantId == null,
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

    // THE COORDINATES ARE CAPTURED FIRST, and unconditionally, before anything
    // else is decided. They are the fact — where the phone was — and they do not
    // depend on whether the user links this to a saved place, agrees to a prompt,
    // or has location permission at all. Everything below is optional; this is
    // not.
    final position = await TransactionLocationService.capturePosition();

    // The proximity question is only asked when there is a fix to ask about, and
    // only when the user has not already chosen a place by hand. Asking over a
    // manual choice would be the app second-guessing them.
    String? locationId = _locationId;
    if (position != null && locationId == null && mounted) {
      final linked = await TransactionLocationService.confirmProximity(
        context,
        locations: context.read<LocationProvider>().locations,
        latitude: position.latitude,
        longitude: position.longitude,
        noun: 'expense',
      );
      if (linked != null) locationId = linked.id;
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
        paymentMethod: _paymentMethod,
        paidByParticipantId: _paidByParticipantId,
        latitude: position?.latitude,
        longitude: position?.longitude,
        // WHEN THE FIX WAS TAKEN, which is not `date`: a transaction logged today
        // for last Tuesday carries Tuesday's date and today's position, and
        // conflating them misreports how fresh the fix is.
        locationCapturedAt: position != null
            ? DateTime.now()
            : widget.existing?.locationCapturedAt,
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

    // The spot-naming offer, AFTER the write, because the cluster count has to
    // include the transaction being saved — asking on the fourth visit has to be
    // able to see all four.
    await _maybeOfferToSaveSpot(provider, position);
    if (!mounted) return;
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

  /// Offers to name the spot, once the same spot has come up often enough.
  ///
  /// Only when this transaction carries coordinates: a cluster is built from
  /// positions, and a transaction with no position cannot join one.
  Future<void> _maybeOfferToSaveSpot(
    TransactionProvider provider,
    Position? position,
  ) async {
    if (position == null || !mounted) return;

    // Already linked to a saved place: there is nothing left to name.
    final locations = context.read<LocationProvider>().locations;
    final candidate = TransactionLocationService.clusterAfterSave(
      transactions: provider.allLiveTransactions(),
      savedLocations: locations,
    );
    if (candidate == null) return;

    final wantsSave = await offerToSaveCluster(
      context,
      candidate,
      noun: 'Spending',
    );
    if (!wantsSave || !mounted) return;

    // Opens the SAME form as the Locations tab's Add button, with the position
    // already filled in — the user is asked for the only thing the app does not
    // know, which is what to call it.
    await AddLocationScreen.show(
      context,
      initialLatitude: candidate.centerLatitude,
      initialLongitude: candidate.centerLongitude,
    );
  }
}

/// Cash or online, as two equal halves of one control.
/// Not a dropdown: there are only two answers, and a two-item menu costs a tap
/// to open and a tap to choose, where this is one tap. Not a switch either,
/// because "Online" is not the negation of "Cash" and a switch invites reading
/// it as on/off.
/// "Paid by" — the one extra field a shared trip asks for.
///
/// A single row of chips rather than a dropdown or a step of its own: the person
/// recording the expense usually is the person who paid, so the common case
/// needs no interaction, and the whole field disappears on a trip that is not
/// shared rather than sitting there disabled.
class _PaidByPicker extends StatelessWidget {
  const _PaidByPicker({
    required this.journey,
    required this.value,
    required this.onChanged,
  });

  final Journey journey;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CategorySectionLabel('Paid by'),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final participant in journey.participants)
              ChoiceChip(
                key: ValueKey('paid-by-${participant.id}'),
                label: Text(
                  participant.id == journey.localParticipantId
                      ? '${participant.name} (you)'
                      : participant.name,
                ),
                selected: participant.id == value,
                onSelected: (_) => onChanged(participant.id),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'One person fronts the amount and everyone splits it evenly. Change '
          'this if someone else handed over the cash.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodPicker extends StatelessWidget {
  const _PaymentMethodPicker({required this.value, required this.onChanged});

  final PaymentMethod value;
  final ValueChanged<PaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CategorySectionLabel('How did you pay?'),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (final method in PaymentMethod.values) ...[
              if (method != PaymentMethod.values.first)
                const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _PaymentMethodOption(
                  method: method,
                  selected: method == value,
                  onTap: () => onChanged(method),
                  textTheme: textTheme,
                  selectedBackground: colorScheme.primaryContainer,
                  selectedForeground: colorScheme.onPrimaryContainer,
                  idleBackground: colorScheme.surfaceContainerHighest,
                  idleForeground: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PaymentMethodOption extends StatelessWidget {
  const _PaymentMethodOption({
    required this.method,
    required this.selected,
    required this.onTap,
    required this.textTheme,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.idleBackground,
    required this.idleForeground,
  });

  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;
  final TextTheme textTheme;
  final Color selectedBackground;
  final Color selectedForeground;
  final Color idleBackground;
  final Color idleForeground;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // A stable identity, so the selected state can be read back rather than
      // inferred from pixel colours.
      key: ValueKey('pay-${method.name}'),
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: 'Pay ${method.label}',
      child: InkWell(
        borderRadius: AppRadii.smallRadius,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? selectedBackground : idleBackground,
            borderRadius: AppRadii.smallRadius,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                method == PaymentMethod.cash
                    ? Icons.payments_rounded
                    : Icons.smartphone_rounded,
                size: 18,
                color: selected ? selectedForeground : idleForeground,
              ),
              const SizedBox(width: AppSpacing.xs),
              // Flexible rather than a fixed gap: "Online" plus its icon has to
              // survive a 360dp phone and a large text scale, and a Row will
              // overflow rather than shrink.
              Flexible(
                child: Text(
                  method.label,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: selected ? selectedForeground : idleForeground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
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
    // Sorted by popularity, then `other` moved back to the end.
    //
    // It leaves the sort wherever its popularity puts it, and `other` is a
    // two-step action sitting in the middle of a list of one-step ones.
    final allMetas = CategoryRegistry.metasOthersLast(
      (ExpenseCategory.values.map((c) => CategoryRegistry.metaFor(c)).toList()
        ..sort((a, b) => a.popularity.compareTo(b.popularity))),
    );

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
