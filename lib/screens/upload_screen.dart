import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../providers/app_providers.dart';
import '../parser/vcf_parser.dart';
import '../services/genomic_drug_scan_service.dart';
import 'genomic_scan_screen.dart';
import 'drug_input_screen.dart';
import 'home_screen.dart';

class UploadScreen extends ConsumerStatefulWidget {
  final bool returnToMedicine;
  final bool returnToDashboard;

  const UploadScreen({
    super.key,
    this.returnToMedicine = false,
    this.returnToDashboard = true,
  });

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
        ref.read(genomicScanReportProvider.notifier).state = GenomicDrugScanService.scan(
          parseResult: parseResult,
          vcfFilename: name,
        );

        setState(() {
          _isValid = true;
          _errorMessage = null;
        });

        if (widget.returnToMedicine && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const DrugInputScreen()),
          );
        } else if (widget.returnToDashboard && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } catch (e) {
      _setError('VCF Parsing Error: ${e.toString()}');
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

  void _scanAllDrugRisks() {
    final parseResult = ref.read(vcfParseResultProvider);
    final filename = ref.read(selectedVcfFilenameProvider);
    if (parseResult == null || filename == null) return;
    final report = GenomicDrugScanService.scan(
      parseResult: parseResult,
      vcfFilename: filename,
    );
    ref.read(genomicScanReportProvider.notifier).state = report;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GenomicScanScreen(report: report)),
    );
  }

  void _checkMedicine() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DrugInputScreen()),
    );
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
                'Analyze Your Genetic Profile',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Upload your VCF file to identify pharmacogenomic information relevant to medicines. Raw VCF data is processed on this device.',
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
              if (_isValid && filename != null) ...[
                FilledButton.icon(
                  onPressed: _isProcessing ? null : _checkMedicine,
                  icon: const Icon(Icons.medication_outlined),
                  label: const Text('CHECK A MEDICINE'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _scanAllDrugRisks,
                  icon: const Icon(Icons.manage_search),
                  label: const Text('CHECK MY MEDICATION RISKS'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Both checks use the validated local medical engine. Raw VCF data stays on this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 20),
              ],

            ],
          ),
        ),
      ),
    );
  }
}
