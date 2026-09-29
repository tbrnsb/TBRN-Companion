import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';

class IncomeDetailScreen extends StatelessWidget {
  const IncomeDetailScreen({super.key, required this.income});

  final Income income;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

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

          _DetailRow(
            icon: meta.icon,
            iconColor: meta.color,
            label: 'Category',
            value: current.effectiveCategoryName,
          ),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: iconColor ?? colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: textTheme.bodyLarge),
              ],
            ),
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
  bool _saving = false;

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
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

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
    setState(() => _saving = true);

    final provider = context.read<TransactionProvider>();
    final description = _descriptionController.text.trim().isEmpty
        ? CategoryRegistry.metaForIncome(_category).name
        : _descriptionController.text.trim();

    if (_isEditing) {
      await provider.updateTransaction(
        widget.existing!.copyWith(
          amount: double.parse(_amountController.text),
          category: _category,
          description: description,
          date: _date,
        ),
      );
      if (mounted) Navigator.pop(context);
      return;
    }

    await provider.addTransaction(
      Income(
        amount: double.parse(_amountController.text),
        category: _category,
        description: description,
        date: _date,
      ),
    );
    if (mounted) Navigator.pop(context);
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
    final categories = IncomeCategory.values;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: categories.map((category) {
        final meta = category.meta;
        // `category.name` is the enum name ("IncomeCategory.salary"), not the
        // stored id, so it must not be used as the label, the selection
        // comparison, or the saved value.
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
