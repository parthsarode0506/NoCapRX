// lib/screens/vcf_upload_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_providers.dart';

class VcfUploadScreen extends ConsumerWidget {
  const VcfUploadScreen({Key? key}) : super(key: key);

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['vcf'],
      withReadStream: true,
    );
    if (result == null) return; // user canceled
    final file = result.files.first;
    // Validate size (<=5MB)
    if (file.size > 5 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File too large (max 5 MB)')),
      );
      return;
    }
    // Store selected file in provider for downstream parsing
    ref.read(selectedVcfProvider.notifier).state = file;
    // Navigate to drug selection screen
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
                  onPressed: () => ref.read(selectedVcfProvider.notifier).state = null, // placeholder
                ),
                ElevatedButton(
                  child: const Text('Missing Info'),
                  onPressed: () => ref.read(selectedVcfProvider.notifier).state = null,
                ),
                ElevatedButton(
                  child: const Text('Malformed'),
                  onPressed: () => ref.read(selectedVcfProvider.notifier).state = null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
