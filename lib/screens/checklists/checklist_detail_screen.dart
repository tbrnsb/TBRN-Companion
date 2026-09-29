import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/screens/checklists/add_checklist_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/iterable_ext.dart';
import 'package:flutter_application_1/widgets/widgets.dart';

/// One checklist, derived from [ChecklistProvider].
///
/// The screen deliberately holds no copy of the record. It used to keep a
/// `late Checklist` taken in initState and rebuild it with a parallel
/// `copyWith` inside a `setState` after every toggle, add, delete and reset,
/// while the provider independently wrote the same change to Hive and
/// notified. Two writers, two copies, and they drifted: a rename made anywhere
/// else was written over by the stale local copy, because the screen read its
/// own field rather than the provider.
class ChecklistDetailScreen extends StatelessWidget {
  final Checklist checklist;

  const ChecklistDetailScreen({super.key, required this.checklist});

  /// The record to render, or null once the provider has loaded and no longer
  /// holds it.
  ///
  /// While the provider is still loading there is nothing to derive from yet,
  /// so the checklist this screen was opened with is used instead. Without that
  /// distinction a cold start would flash a "removed" state before the first
  /// load finished.
  Checklist? _live(BuildContext context) {
    final provider = context.watch<ChecklistProvider>();
    if (provider.isLoading) return null;
    return provider.checklists.where((c) => c.id == checklist.id).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChecklistProvider>();
    final current = _live(context);

    if (current == null && !provider.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(checklist.name), elevation: 0),
        body: Center(
          child: Padding(
            padding: AppSpacing.screenPadding,
            child: Text(
              'This checklist is no longer available.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    final shown = current ?? checklist;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final checkedCount = shown.items.where((i) => i.isChecked).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(shown.name),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
              if (checkedCount > 0)
                const PopupMenuItem(
                  value: 'clearCompleted',
                  child: Text('Clear packed items'),
                ),
              const PopupMenuItem(value: 'reset', child: Text('Uncheck all')),
            ],
            // Every case is explicit and breaks. Dart already inserts an
            // implicit break when a clause ends in a void call, so the missing
            // `break`s were not causing fall-through — but an explicit one keeps
            // a future non-void edit to a clause from silently running the next
            // action.
            onSelected: (value) async {
              switch (value) {
                case 'rename':
                  // AddChecklistScreen persists the change and notifies; there
                  // is nothing to mirror back into the screen.
                  await Navigator.of(context).push<Checklist>(
                    MaterialPageRoute(
                      builder: (_) => AddChecklistScreen(checklist: shown),
                    ),
                  );
                  break;
                case 'duplicate':
                  await context.read<ChecklistProvider>().duplicateChecklist(
                    shown.id,
                  );
                  break;
                case 'clearCompleted':
                  await context.read<ChecklistProvider>().clearCompletedItems(
                    shown.id,
                  );
                  break;
                case 'reset':
                  _showResetConfirmation(context, shown);
                  break;
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress bar
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Progress', style: textTheme.titleSmall),
                    // The one number this screen is about, so it is the one
                    // number allowed to be large.
                    Text(
                      '${(shown.getProgress() * 100).toStringAsFixed(0)}%',
                      style: textTheme.headlineMedium,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                AppProgressBar(
                  value: shown.getProgress(),
                  minHeight: AppSpacing.xs,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$checkedCount of ${shown.items.length} items checked',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Items list
          Expanded(
            child: shown.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.done_all,
                          size: 64,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text('No items yet', style: textTheme.titleMedium),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    itemCount: shown.items.length,
                    separatorBuilder: (_, index) =>
                        Divider(height: 1, color: colorScheme.outlineVariant),
                    itemBuilder: (context, index) {
                      return _buildItemTile(
                        context,
                        provider,
                        shown.items[index],
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddItemDialog(context, shown),
        tooltip: 'Add Item',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildItemTile(
    BuildContext context,
    ChecklistProvider provider,
    ChecklistItem item,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: item.isChecked,
        // The provider persists the toggle and notifies, which rebuilds this
        // screen from the new record. No local write is needed or wanted.
        onChanged: (value) => provider.toggleItem(item.id),
      ),
      title: AppCheckableLabel(text: item.name, checked: item.isChecked),
      trailing: IconButton(
        icon: Icon(
          Icons.delete_outline_rounded,
          color: Theme.of(context).colorScheme.error,
        ),
        onPressed: () => _showDeleteItemConfirmation(context, provider, item),
      ),
    );
  }

  void _showAddItemDialog(BuildContext context, Checklist current) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Item'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(hintText: 'Enter item name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                context.read<ChecklistProvider>().addItemToChecklist(
                  current.id,
                  ChecklistItem(checklistId: current.id, name: name),
                );
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showDeleteItemConfirmation(
    BuildContext context,
    ChecklistProvider provider,
    ChecklistItem item,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.deleteChecklistItem(item.id);
              Navigator.pop(dialogContext);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showResetConfirmation(BuildContext context, Checklist current) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Checklist?'),
        content: const Text('This will uncheck all items. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<ChecklistProvider>().resetChecklist(current.id);
              Navigator.pop(dialogContext);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
