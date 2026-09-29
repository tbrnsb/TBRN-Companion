import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          const SizedBox(height: AppSpacing.md),

          _SettingsSection(
            title: 'Currency',
            child: Column(
              children: [
                _CurrencyOption(
                  currency: Currency.rs,
                  selected: settings.currency,
                  onSelect: (currency) => settings.setCurrency(currency),
                ),
                _CurrencyOption(
                  currency: Currency.usd,
                  selected: settings.currency,
                  onSelect: (currency) => settings.setCurrency(currency),
                ),
                _CurrencyOption(
                  currency: Currency.eur,
                  selected: settings.currency,
                  onSelect: (currency) => settings.setCurrency(currency),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          _SettingsSection(
            title: 'Theme',
            child: Column(
              children: [
                _ThemeOption(
                  mode: ThemeMode.light,
                  selected: settings.themeMode,
                  onSelect: (mode) => settings.setThemeMode(mode),
                ),
                _ThemeOption(
                  mode: ThemeMode.dark,
                  selected: settings.themeMode,
                  onSelect: (mode) => settings.setThemeMode(mode),
                ),
                _ThemeOption(
                  mode: ThemeMode.system,
                  selected: settings.themeMode,
                  onSelect: (mode) => settings.setThemeMode(mode),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          const _DemoSection(),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Card(child: child),
      ],
    );
  }
}

class _CurrencyOption extends StatelessWidget {
  const _CurrencyOption({
    required this.currency,
    required this.selected,
    required this.onSelect,
  });

  final Currency currency;
  final Currency selected;
  final ValueChanged<Currency> onSelect;

  @override
  Widget build(BuildContext context) {
    final isSelected = currency == selected;
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.money_rounded, color: colorScheme.primary),
      title: Text(currency.name),
      trailing: isSelected
          ? Icon(Icons.check, color: colorScheme.primary)
          : null,
      onTap: () => onSelect(currency),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.mode,
    required this.selected,
    required this.onSelect,
  });

  final ThemeMode mode;
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final isSelected = mode == selected;
    final colorScheme = Theme.of(context).colorScheme;

    String label;
    switch (mode) {
      case ThemeMode.light:
        label = 'Light';
        break;
      case ThemeMode.dark:
        label = 'Dark';
        break;
      case ThemeMode.system:
        label = 'System';
        break;
    }

    return ListTile(
      leading:
          Icon(Icons.brightness_6_rounded, color: colorScheme.primary),
      title: Text(label),
      trailing: isSelected
          ? Icon(Icons.check, color: colorScheme.primary)
          : null,
      onTap: () => onSelect(mode),
    );
  }
}

class _DemoSection extends StatefulWidget {
  const _DemoSection();

  @override
  State<_DemoSection> createState() => _DemoSectionState();
}

class _DemoSectionState extends State<_DemoSection> {
  bool _loading = false;

  Future<void> _addDemo() async {
    setState(() => _loading = true);
    await showDialog(
      context: context,
      builder: (context) => const _AddDemoDialog(),
    );
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _clearDemo() async {
    await showDialog(
      context: context,
      builder: (context) => const _ClearDemoDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Demo Data',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Test data for demo purposes.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _addDemo,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add Demo Data'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _clearDemo,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Clear Data'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AddDemoDialog extends StatelessWidget {
  const _AddDemoDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Demo Data?'),
      content: const Text(
        'This will add sample expenses and incomes '
        'for testing purposes. These are clearly labeled as demo data '
        'and can be removed via the Clear Data button.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            await context.read<TransactionProvider>().addDemoData();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Add Demo Data'),
        ),
      ],
    );
  }
}

class _ClearDemoDialog extends StatelessWidget {
  const _ClearDemoDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clear All Data?'),
      content: const Text(
        'This will remove all transactions (both demo and real). '
        'Use with caution.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            await context.read<TransactionProvider>().clearDemoData();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Clear All'),
        ),
      ],
    );
  }
}