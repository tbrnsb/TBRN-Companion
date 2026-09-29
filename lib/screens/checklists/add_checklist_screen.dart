import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';

class AddChecklistScreen extends StatefulWidget {
  final Checklist? checklist;

  const AddChecklistScreen({super.key, this.checklist, this.journeyId});

  /// Preselected journey when creating a checklist from a journey page.
  final String? journeyId;

  @override
  State<AddChecklistScreen> createState() => _AddChecklistScreenState();
}

class _AddChecklistScreenState extends State<AddChecklistScreen> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late bool _isEverydayEssentials;
  String? _selectedLocationId;
  String? _selectedJourneyId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.checklist?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.checklist?.description ?? '',
    );
    _isEverydayEssentials = widget.checklist?.isEverydayEssentials ?? false;
    _selectedLocationId = widget.checklist?.linkedLocationId;
    _selectedJourneyId = widget.checklist?.journeyId ?? widget.journeyId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locations = context.watch<LocationProvider>().locations;
    final journeys = context.watch<JourneyProvider>().journeys;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.checklist == null ? 'New Checklist' : 'Edit Checklist',
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Checklist Name',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'e.g., Office Work, Gym Day',
              ),
            ),
            const SizedBox(height: 24),
            Text('Description', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                hintText: 'What is this checklist for?',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            if (journeys.isNotEmpty) ...[
              Text('Journey', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _selectedJourneyId,
                decoration: const InputDecoration(
                  hintText: 'Link this checklist to a journey',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No journey'),
                  ),
                  ...journeys.map(
                    (journey) => DropdownMenuItem<String?>(
                      value: journey.id,
                      child: Text(journey.title),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _selectedJourneyId = value),
              ),
              const SizedBox(height: 24),
            ],
            if (locations.isNotEmpty) ...[
              Text(
                'Linked location',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _selectedLocationId,
                decoration: const InputDecoration(
                  hintText: 'No linked location',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No linked location'),
                  ),
                  ...locations.map(
                    (location) => DropdownMenuItem<String?>(
                      value: location.id,
                      child: Text(location.name),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _selectedLocationId = value),
              ),
              const SizedBox(height: 24),
            ],
            Card(
              child: CheckboxListTile(
                title: const Text('Everyday Essentials'),
                subtitle: const Text(
                  'Items you never leave without (phone, wallet, keys)',
                ),
                value: _isEverydayEssentials,
                onChanged: (value) {
                  setState(() {
                    _isEverydayEssentials = value ?? false;
                  });
                },
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saveChecklist,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    widget.checklist == null
                        ? 'Create Checklist'
                        : 'Save Changes',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveChecklist() {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a checklist name')),
      );
      return;
    }

    final provider = context.read<ChecklistProvider>();

    if (widget.checklist == null) {
      final newChecklist = Checklist(
        name: _nameController.text,
        description: _descriptionController.text,
        linkedLocationId: _selectedLocationId,
        journeyId: _selectedJourneyId,
        isEverydayEssentials: _isEverydayEssentials,
      );
      provider.addChecklist(newChecklist);
    } else {
      final updatedChecklist = widget.checklist!.copyWith(
        name: _nameController.text,
        description: _descriptionController.text,
        linkedLocationId: _selectedLocationId,
        journeyId: _selectedJourneyId,
        isEverydayEssentials: _isEverydayEssentials,
      );
      provider.updateChecklist(updatedChecklist);
    }

    Navigator.pop(context);
  }
}
