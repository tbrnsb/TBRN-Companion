import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/screens/checklists/add_checklist_screen.dart';

class ChecklistDetailScreen extends StatefulWidget {
  final Checklist checklist;

  const ChecklistDetailScreen({super.key, required this.checklist});

  @override
  State<ChecklistDetailScreen> createState() => _ChecklistDetailScreenState();
}

class _ChecklistDetailScreenState extends State<ChecklistDetailScreen> {
  late Checklist _checklist;

  @override
  void initState() {
    super.initState();
    _checklist = widget.checklist;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_checklist.name),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
              if (_checklist.items.any((i) => i.isChecked))
                const PopupMenuItem(
                  value: 'clearCompleted',
                  child: Text('Clear packed items'),
                ),
              const PopupMenuItem(value: 'reset', child: Text('Uncheck all')),
            ],
            onSelected: (value) async {
              switch (value) {
                case 'rename':
                  final updated = await Navigator.of(context).push<Checklist>(
                    MaterialPageRoute(
                      builder: (_) => AddChecklistScreen(checklist: _checklist),
                    ),
                  );
                  if (updated != null && mounted) {
                    setState(() => _checklist = updated);
                  }
                case 'duplicate':
                  await context.read<ChecklistProvider>().duplicateChecklist(
                    _checklist.id,
                  );
                case 'clearCompleted':
                  await context.read<ChecklistProvider>().clearCompletedItems(
                    _checklist.id,
                  );
                  setState(() {
                    _checklist = _checklist.copyWith(
                      items: _checklist.items
                          .where((i) => !i.isChecked)
                          .toList(),
                    );
                  });
                case 'reset':
                  _showResetConfirmation(context);
              }
            },
          ),
        ],
      ),
      body: Consumer<ChecklistProvider>(
        builder: (context, checklistProvider, _) {
          return Column(
            children: [
              // Progress bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Progress',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${(_checklist.getProgress() * 100).toStringAsFixed(0)}%',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _checklist.getProgress(),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_checklist.items.where((i) => i.isChecked).length} of ${_checklist.items.length} items checked',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Items list
              Expanded(
                child: _checklist.items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.done_all,
                              size: 64,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No items yet',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _checklist.items.length,
                        separatorBuilder: (_, index) => Divider(
                          height: 1,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        itemBuilder: (context, index) {
                          final item = _checklist.items[index];
                          return _buildItemTile(
                            context,
                            checklistProvider,
                            item,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddItemDialog(context),
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
        onChanged: (value) {
          provider.toggleItem(item.id);
          setState(() {
            _checklist = _checklist.copyWith(
              items: _checklist.items.map((i) {
                if (i.id == item.id) {
                  return i.copyWith(isChecked: !i.isChecked);
                }
                return i;
              }).toList(),
            );
          });
        },
      ),
      title: Text(
        item.name,
        style: TextStyle(
          color: item.isChecked
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : null,
          decoration: item.isChecked ? TextDecoration.lineThrough : null,
        ),
      ),
      trailing: IconButton(
        icon: Icon(
          Icons.delete_outline_rounded,
          color: Theme.of(context).colorScheme.error,
        ),
        onPressed: () => _showDeleteItemConfirmation(context, provider, item),
      ),
    );
  }

  void _showAddItemDialog(BuildContext context) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Item'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(hintText: 'Enter item name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                final item = ChecklistItem(
                  checklistId: _checklist.id,
                  name: textController.text,
                );
                context.read<ChecklistProvider>().addItemToChecklist(
                  _checklist.id,
                  item,
                );
                setState(() {
                  _checklist = _checklist.copyWith(
                    items: [..._checklist.items, item],
                  );
                });
                Navigator.pop(context);
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
      builder: (context) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.deleteChecklistItem(item.id);
              setState(() {
                _checklist = _checklist.copyWith(
                  items: _checklist.items
                      .where((i) => i.id != item.id)
                      .toList(),
                );
              });
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showResetConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Checklist?'),
        content: const Text('This will uncheck all items. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<ChecklistProvider>().resetChecklist(_checklist.id);
              setState(() {
                _checklist = _checklist.copyWith(
                  items: _checklist.items
                      .map((i) => i.copyWith(isChecked: false))
                      .toList(),
                );
              });
              Navigator.pop(context);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
