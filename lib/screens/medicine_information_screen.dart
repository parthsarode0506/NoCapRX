import 'package:flutter/material.dart';

import '../models/drug_evidence.dart';
import '../features/chat/ask_nocaprx_screen.dart';

class MedicineInformationScreen extends StatelessWidget {
  final DrugEvidence evidence;

  const MedicineInformationScreen({super.key, required this.evidence});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Medicine Information')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(evidence.displayName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Active ingredient: ${evidence.activeIngredients.isEmpty ? evidence.genericName : evidence.activeIngredients.join(', ')}'),
            if (evidence.dosageForm != null) Text('Form: ${evidence.dosageForm}'),
            if (evidence.strength != null) Text('Strength: ${evidence.strength}'),
            const SizedBox(height: 16),
            _section('What is it used for?', evidence.uses, Icons.medication_outlined),
            _section('Common side effects', evidence.commonSideEffects, Icons.info_outline),
            _section('Serious side effects / warning signs', evidence.seriousSideEffects, Icons.warning_amber_outlined),
            _section('Important precautions', evidence.precautions, Icons.health_and_safety_outlined),
            const SizedBox(height: 12),
            Text('Evidence: ${evidence.source}', style: theme.textTheme.bodySmall),
            if (evidence.evidenceLevel.isNotEmpty) Text('Evidence level: ${evidence.evidenceLevel}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AskNocapRxScreen(medicineName: evidence.genericName))),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Ask NOCAPRx about this medicine'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue to personalize assessment'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<String> items, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 20), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)))]),
          const SizedBox(height: 8),
          if (items.isEmpty) const Text('No structured information is available in the verified evidence record.'),
          ...items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $item'))),
        ]),
      ),
    );
  }
}