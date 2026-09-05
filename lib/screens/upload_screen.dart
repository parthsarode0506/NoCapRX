import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../providers/app_providers.dart';
import '../parser/vcf_parser.dart';
import 'drug_input_screen.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  String? _errorMessage;
  bool _isValid = false;
  bool _isProcessing = false;

  Future<void> _pickVcfFile() async {
    setState(() {
      _errorMessage = null;
      _isProcessing = true;
    });

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['vcf'],
        // Web browsers cannot supply PlatformFile.path. Request the file bytes
        // explicitly so parsing stays fully on-device on every platform.
      );

      if (files.isNotEmpty) {
        final platformFile = files.first;
        final name = platformFile.name;

        if (!name.toLowerCase().endsWith('.vcf')) {
          _setError('Invalid file extension. Please select a .vcf file.');
          return;
        }

        final bytes = await platformFile.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024) {
          _setError('File size exceeds the 5MB limit.');
          return;
        }

        final content = utf8.decode(bytes);

        if (content.trim().isEmpty) {
          _setError('The selected VCF file is empty.');
          return;
        }

        // Validate content with VCF parser
        final parseResult = VcfParser.parseVcfContent(content);

        ref.read(selectedVcfFilenameProvider.notifier).state = name;
        ref.read(selectedVcfContentProvider.notifier).state = content;
        ref.read(vcfParseResultProvider.notifier).state = parseResult;

        setState(() {
          _isValid = true;
          _errorMessage = null;
        });
      }
    } catch (e) {
      _setError('VCF Parsing Error: ${e.toString()}');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _loadSampleVcf(String assetPath, String sampleName) async {
    setState(() {
      _errorMessage = null;
      _isProcessing = true;
    });

    try {
      final content = await rootBundle.loadString(assetPath);
      
      if (sampleName.contains('malformed')) {
        // Will throw VcfParseException
        VcfParser.parseVcfContent(content);
      }

      final parseResult = VcfParser.parseVcfContent(content);

      ref.read(selectedVcfFilenameProvider.notifier).state = sampleName;
      ref.read(selectedVcfContentProvider.notifier).state = content;
      ref.read(vcfParseResultProvider.notifier).state = parseResult;

      setState(() {
        _isValid = true;
        _errorMessage = null;
      });
    } catch (e) {
      _setError('Sample Error ($sampleName): ${e.toString()}');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _setError(String msg) {
    ref.read(selectedVcfFilenameProvider.notifier).state = null;
    ref.read(selectedVcfContentProvider.notifier).state = null;
    ref.read(vcfParseResultProvider.notifier).state = null;
    setState(() {
      _errorMessage = msg;
      _isValid = false;
    });
  }

  void _removeFile() {
    ref.read(selectedVcfFilenameProvider.notifier).state = null;
    ref.read(selectedVcfContentProvider.notifier).state = null;
    ref.read(vcfParseResultProvider.notifier).state = null;
    setState(() {
      _errorMessage = null;
      _isValid = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filename = ref.watch(selectedVcfFilenameProvider);
    final parseResult = ref.watch(vcfParseResultProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Genetic Data'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Step 1: Select Patient VCF File',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'PharmaGuard processes genetic data 100% on your device. Raw VCF lines are never uploaded to cloud servers.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),

              // File Picker Dropzone Area
              InkWell(
                onTap: _isProcessing ? null : _pickVcfFile,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                  decoration: BoxDecoration(
                    color: _isValid
                        ? Colors.green.shade50
                        : theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isValid ? Colors.green : theme.colorScheme.primary.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _isValid ? Icons.check_circle_rounded : Icons.cloud_upload_rounded,
                        size: 54,
                        color: _isValid ? Colors.green : theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isValid ? 'VCF File Loaded & Validated' : 'Tap to Browse .VCF File',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _isValid ? Colors.green.shade800 : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Supports VCF v4.2 (Max size: 5MB)',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Error Display Box
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade900, fontSize: 13, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // File Info Card when selected
              if (_isValid && filename != null) ...[
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.insert_drive_file, color: Colors.blueAccent),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      filename,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: _removeFile,
                              tooltip: 'Remove File',
                            ),
                          ],
                        ),
                        if (parseResult != null) ...[
                          const Divider(),
                          Text(
                            'Parsing Quality Summary:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 4),
                          Text('• Target Genes Detected: ${parseResult.qualityMetrics.genesCovered.join(', ')}', style: const TextStyle(fontSize: 12)),
                          Text('• Total Variants: ${parseResult.qualityMetrics.variantsDetected}', style: const TextStyle(fontSize: 12)),
                          Text('• Annotation Completeness: ${(parseResult.qualityMetrics.annotationCompleteness * 100).toInt()}%', style: const TextStyle(fontSize: 12)),
                          if (parseResult.qualityMetrics.diplotypeInferred)
                            const Text('• Note: One or more alleles defaulted to *1 (Inferred)', style: TextStyle(fontSize: 12, color: Colors.orange)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Quick Sample Files for Testing Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Demo Test Samples:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                          label: const Text('Clean VCF Sample'),
                          onPressed: () => _loadSampleVcf('assets/samples/sample_clean.vcf', 'sample_clean.vcf'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.warning_amber_outlined, size: 16, color: Colors.orange),
                          label: const Text('Missing INFO Sample'),
                          onPressed: () => _loadSampleVcf('assets/samples/sample_missing_info.vcf', 'sample_missing_info.vcf'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.error_outline, size: 16, color: Colors.red),
                          label: const Text('Malformed Sample'),
                          onPressed: () => _loadSampleVcf('assets/samples/sample_malformed.vcf', 'sample_malformed.vcf'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Next Button
              ElevatedButton(
                onPressed: _isValid
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const DrugInputScreen()),
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Next: Select Drugs',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
