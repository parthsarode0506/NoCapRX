// lib/screens/vcf_upload_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_providers.dart';

class VcfUploadScreen extends ConsumerWidget {
  const VcfUploadScreen({super.key});

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['vcf'],
    );
    if (files.isEmpty) return; // user canceled
    final file = files.first;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    if (bytes.length > 5 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File too large (max 5 MB)')),
      );
      return;
    }
    ref.read(selectedVcfFilenameProvider.notifier).state = file.name;
    ref.read(selectedVcfContentProvider.notifier).state = utf8.decode(bytes);
    // Navigate to drug selection screen
    if (!context.mounted) return;
    Navigator.of(context).pushNamed('/drug_input');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload VCF')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Select VCF File'),
              onPressed: () => _pickFile(context, ref),
            ),
            const SizedBox(height: 24),
            const Text('Sample VCF files for testing:'),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  child: const Text('Clean Sample'),
                  onPressed: () => ref.read(selectedVcfContentProvider.notifier).state = null,
                ),
                ElevatedButton(
                  child: const Text('Missing Info'),
                  onPressed: () => ref.read(selectedVcfContentProvider.notifier).state = null,
                ),
                ElevatedButton(
                  child: const Text('Malformed'),
                  onPressed: () => ref.read(selectedVcfContentProvider.notifier).state = null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
